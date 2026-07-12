import Darwin
import Foundation

final class RelayHTTPServer {
    typealias DeliveryHandler = (CapturePayload, StoredCapture, RelaySettings) throws -> Void

    private let settingsProvider: () throws -> RelaySettings
    private let statusStore: DeliveryStatusStore
    private let eventHandler: (RelayEvent) -> Void
    private let deliveryHandler: DeliveryHandler
    private let maxBodyBytes = 12_500_000
    private let maxHeaderBytes = 32 * 1024
    private let requestTimeoutNanoseconds: UInt64
    private let connectionLimiter: ConnectionLimiter
    private let acceptQueue = DispatchQueue(label: "app.cmdcmd.relay.http.accept", qos: .userInitiated)
    private let connectionQueue = DispatchQueue(label: "app.cmdcmd.relay.http.connection", qos: .userInitiated, attributes: .concurrent)
    private let deliveryQueue = DispatchQueue(label: "app.cmdcmd.relay.delivery", qos: .userInitiated)
    private var listenSocket: Int32 = -1
    private var isStopping = false
    private(set) var listeningPort: Int?

    init(
        settingsProvider: @escaping () throws -> RelaySettings,
        statusStore: DeliveryStatusStore,
        eventHandler: @escaping (RelayEvent) -> Void,
        deliveryHandler: DeliveryHandler? = nil,
        requestTimeout: TimeInterval = 15,
        maximumConcurrentConnections: Int = 16
    ) {
        let timeoutNanoseconds = requestTimeout * 1_000_000_000
        precondition(
            timeoutNanoseconds.isFinite
                && timeoutNanoseconds >= 1
                && timeoutNanoseconds <= Double(UInt64.max)
        )
        precondition(maximumConcurrentConnections > 0)
        self.settingsProvider = settingsProvider
        self.statusStore = statusStore
        self.eventHandler = eventHandler
        self.deliveryHandler = deliveryHandler ?? Self.deliver
        requestTimeoutNanoseconds = UInt64(timeoutNanoseconds)
        connectionLimiter = ConnectionLimiter(maximumCount: maximumConcurrentConnections)
    }

    var activeConnectionCount: Int {
        connectionLimiter.activeCount
    }

    func start() throws {
        let settings = try settingsProvider()
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw RelayHTTPError.server("Could not create relay socket.")
        }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var noSigPipe: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(settings.port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(settings.host))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(socketFD)
            throw RelayHTTPError.server("Could not bind relay to \(settings.host):\(settings.port).")
        }

        guard Darwin.listen(socketFD, SOMAXCONN) == 0 else {
            Darwin.close(socketFD)
            throw RelayHTTPError.server("Could not listen on \(settings.host):\(settings.port).")
        }

        listeningPort = try Self.localPort(for: socketFD)
        listenSocket = socketFD
        isStopping = false
        acceptQueue.async { [weak self] in
            self?.acceptLoop(socketFD: socketFD)
        }
    }

    func stop() {
        isStopping = true
        if listenSocket >= 0 {
            Darwin.shutdown(listenSocket, SHUT_RDWR)
            Darwin.close(listenSocket)
            listenSocket = -1
            listeningPort = nil
        }
    }

    private func acceptLoop(socketFD: Int32) {
        while !isStopping {
            var clientAddress = sockaddr()
            var clientAddressLength = socklen_t(MemoryLayout<sockaddr>.size)
            let clientFD = Darwin.accept(socketFD, &clientAddress, &clientAddressLength)
            if clientFD < 0 {
                if !isStopping {
                    eventHandler(.failed("Relay accept failed."))
                }
                continue
            }

            guard connectionLimiter.tryAcquire() else {
                writeResponse(
                    .json(statusCode: 503, body: ["error": "Relay is busy."]),
                    to: clientFD
                )
                Darwin.close(clientFD)
                continue
            }

            connectionQueue.async { [weak self, connectionLimiter] in
                defer { connectionLimiter.release() }
                guard let self else {
                    Darwin.close(clientFD)
                    return
                }
                self.handleConnection(clientFD)
            }
        }
    }

    private func handleConnection(_ clientFD: Int32) {
        defer { Darwin.close(clientFD) }

        do {
            let request = try readRequest(from: clientFD)
            let response = try handle(request)
            writeResponse(response, to: clientFD)
        } catch let error as RelayHTTPError {
            let message = error.statusCode >= 500 ? "Internal relay error." : error.localizedDescription
            writeResponse(.json(statusCode: error.statusCode, body: ["error": message]), to: clientFD)
        } catch {
            writeResponse(.json(statusCode: 500, body: ["error": "Internal relay error."]), to: clientFD)
        }
    }

    private func handle(_ request: HTTPRequest) throws -> HTTPResponse {
        if request.method == "GET", request.path == "/healthz" {
            return .json(
                statusCode: 200,
                body: [
                    "relay": "cmdcmd-native",
                    "status": "ok"
                ]
            )
        }

        let settings = try settingsProvider()
        guard isAuthorized(request.headers["authorization"], expectedToken: settings.token) else {
            throw RelayHTTPError.unauthorized
        }

        if request.method == "GET" {
            guard let captureId = captureIdFromStatusPath(request.path) else {
                throw RelayHTTPError.notFound("Not found.")
            }
            guard let status = statusStore.status(captureId: captureId) else {
                throw RelayHTTPError.notFound("Capture status not found.")
            }
            return .json(statusCode: 200, encodable: status)
        }

        guard request.method == "POST", request.path == "/v1/captures" else {
            throw RelayHTTPError.notFound("Not found.")
        }
        guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
            throw RelayHTTPError.unsupportedMediaType("Content-Type must be application/json.")
        }

        let capture = try CapturePayload.decode(from: request.body)
        let stored = try CaptureStorage.persist(capture, inboxDirectory: settings.inboxDirectory)
        statusStore.accept(captureId: capture.captureId, deliveryMode: settings.deliveryMode)
        eventHandler(.accepted(capture.captureId))

        deliveryQueue.async { [statusStore, eventHandler, deliveryHandler] in
            statusStore.delivering(captureId: capture.captureId, deliveryMode: settings.deliveryMode)
            eventHandler(.delivering(capture.captureId))
            do {
                try deliveryHandler(capture, stored, settings)
                statusStore.delivered(captureId: capture.captureId, deliveryMode: settings.deliveryMode)
                eventHandler(.delivered(capture.captureId))
            } catch {
                statusStore.failed(captureId: capture.captureId, error: error, deliveryMode: settings.deliveryMode)
                eventHandler(.failed(error.localizedDescription))
            }
        }

        return .json(
            statusCode: 202,
            body: [
                "status": "accepted",
                "captureId": capture.captureId,
                "deliveryMode": settings.deliveryMode.rawValue,
                "imagePath": stored.imagePath,
                "metadataPath": stored.metadataPath,
                "statusUrl": "/v1/captures/\(capture.captureId)/status"
            ]
        )
    }

    private func readRequest(from clientFD: Int32) throws -> HTTPRequest {
        let (deadline, deadlineOverflow) = DispatchTime.now().uptimeNanoseconds
            .addingReportingOverflow(requestTimeoutNanoseconds)
        guard !deadlineOverflow else {
            throw RelayHTTPError.server("Could not configure request deadline.")
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        var requestHead: HTTPRequestHead?
        var headerEndIndex: Data.Index?

        while true {
            try configureReceiveTimeout(for: clientFD, deadline: deadline)
            let count = Darwin.recv(clientFD, &buffer, buffer.count, 0)
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw RelayHTTPError.requestTimeout
                }
                throw RelayHTTPError.badRequest("Could not read request.")
            }
            if count == 0 {
                break
            }

            data.append(buffer, count: count)

            if headerEndIndex == nil, let range = data.range(of: Data([13, 10, 13, 10])) {
                guard range.lowerBound <= maxHeaderBytes else {
                    throw RelayHTTPError.badRequest("HTTP headers are too large.")
                }
                headerEndIndex = range.upperBound
                let headerData = data[..<range.lowerBound]
                let headerText = String(decoding: headerData, as: UTF8.self)
                requestHead = try HTTPRequest.parseHead(headerText: headerText, maxBodyBytes: maxBodyBytes)
            } else if headerEndIndex == nil, data.count > maxHeaderBytes + 3 {
                throw RelayHTTPError.badRequest("HTTP headers are too large.")
            }

            if let headerEndIndex, let requestHead {
                let (requestEndIndex, overflow) = headerEndIndex.addingReportingOverflow(requestHead.contentLength)
                guard !overflow else {
                    throw RelayHTTPError.payloadTooLarge
                }
                if data.count >= requestEndIndex {
                    break
                }
                if data.count - headerEndIndex > maxBodyBytes {
                    throw RelayHTTPError.payloadTooLarge
                }
            }
        }

        guard let headerEndIndex, let requestHead else {
            throw RelayHTTPError.badRequest("Malformed HTTP request.")
        }

        let (requestEndIndex, overflow) = headerEndIndex.addingReportingOverflow(requestHead.contentLength)
        guard !overflow, requestEndIndex <= data.count else {
            throw RelayHTTPError.badRequest("Incomplete HTTP request body.")
        }
        return HTTPRequest(
            method: requestHead.method,
            path: requestHead.path,
            headers: requestHead.headers,
            body: Data(data[headerEndIndex..<requestEndIndex])
        )
    }

    private func configureReceiveTimeout(for clientFD: Int32, deadline: UInt64) throws {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else {
            throw RelayHTTPError.requestTimeout
        }

        let remainingNanoseconds = deadline - now
        let remainingMicroseconds = max(
            UInt64(1),
            (remainingNanoseconds + 999) / 1_000
        )
        var timeout = timeval(
            tv_sec: Int(remainingMicroseconds / 1_000_000),
            tv_usec: Int32(remainingMicroseconds % 1_000_000)
        )
        guard setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            throw RelayHTTPError.server("Could not configure request timeout.")
        }
    }

    private func writeResponse(_ response: HTTPResponse, to clientFD: Int32) {
        let data = response.serialized()
        data.withUnsafeBytes { pointer in
            guard let baseAddress = pointer.baseAddress else {
                return
            }
            var sent = 0
            while sent < data.count {
                let count = Darwin.send(clientFD, baseAddress.advanced(by: sent), data.count - sent, 0)
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else {
                    return
                }
                sent += count
            }
        }
    }

    private func isAuthorized(_ authorizationHeader: String?, expectedToken: String) -> Bool {
        guard let authorizationHeader,
              authorizationHeader.lowercased().hasPrefix("bearer ") else {
            return false
        }
        let token = String(authorizationHeader.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        let actualBytes = Array(token.utf8)
        let expectedBytes = Array(expectedToken.utf8)
        guard actualBytes.count == expectedBytes.count else {
            return false
        }
        var diff: UInt8 = 0
        for index in actualBytes.indices {
            diff |= actualBytes[index] ^ expectedBytes[index]
        }
        return diff == 0
    }

    private func captureIdFromStatusPath(_ path: String) -> String? {
        let prefix = "/v1/captures/"
        let suffix = "/status"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else {
            return nil
        }
        let start = path.index(path.startIndex, offsetBy: prefix.count)
        let end = path.index(path.endIndex, offsetBy: -suffix.count)
        return String(path[start..<end]).removingPercentEncoding
    }

    private static func deliver(
        capture: CapturePayload,
        stored: StoredCapture,
        settings: RelaySettings
    ) throws {
        switch settings.deliveryMode {
        case .codex:
            try DesktopDelivery.deliver(capture: capture, stored: stored, settings: settings)
        case .reviewInbox:
            try ReviewInboxDelivery.deliver(capture: capture, stored: stored, settings: settings)
        }
    }

    private static func localPort(for socketFD: Int32) throws -> Int {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(socketFD, $0, &length)
            }
        }
        guard result == 0 else {
            Darwin.close(socketFD)
            throw RelayHTTPError.server("Could not read relay socket address.")
        }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

enum RelayEvent {
    case ready(String)
    case accepted(String)
    case delivering(String)
    case delivered(String)
    case failed(String)
}

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    init(headerText: String, body: Data, maxBodyBytes: Int = 12_500_000) throws {
        let head = try Self.parseHead(headerText: headerText, maxBodyBytes: maxBodyBytes)
        guard body.count == head.contentLength else {
            throw RelayHTTPError.badRequest("HTTP body length does not match Content-Length.")
        }
        self.init(method: head.method, path: head.path, headers: head.headers, body: body)
    }

    init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    static func parseHead(headerText: String, maxBodyBytes: Int) throws -> HTTPRequestHead {
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw RelayHTTPError.badRequest("Malformed HTTP request.")
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw RelayHTTPError.badRequest("Malformed HTTP request line.")
        }

        let method = requestParts[0].uppercased()
        let path = requestParts[1]
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty, let separator = line.firstIndex(of: ":") else {
                throw RelayHTTPError.badRequest("Malformed HTTP header.")
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else {
                throw RelayHTTPError.badRequest("HTTP header name must not be empty.")
            }
            guard headers[key] == nil else {
                throw RelayHTTPError.badRequest("Duplicate HTTP header: \(key).")
            }
            headers[key] = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard headers["transfer-encoding"] == nil else {
            throw RelayHTTPError.badRequest("Transfer-Encoding is not supported.")
        }

        let contentLength: Int
        if let value = headers["content-length"] {
            guard !value.isEmpty,
                  value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let length = Int(value) else {
                throw RelayHTTPError.badRequest("Content-Length must be a non-negative decimal integer.")
            }
            guard length <= maxBodyBytes else {
                throw RelayHTTPError.payloadTooLarge
            }
            contentLength = length
        } else {
            guard method != "POST" else {
                throw RelayHTTPError.badRequest("Content-Length is required for POST requests.")
            }
            contentLength = 0
        }

        return HTTPRequestHead(method: method, path: path, headers: headers, contentLength: contentLength)
    }
}

struct HTTPRequestHead {
    var method: String
    var path: String
    var headers: [String: String]
    var contentLength: Int
}

private struct HTTPResponse {
    var statusCode: Int
    var reason: String
    var body: Data

    static func json(statusCode: Int, body: [String: String]) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        return HTTPResponse(statusCode: statusCode, reason: reasonPhrase(statusCode), body: data)
    }

    static func json<T: Encodable>(statusCode: Int, encodable: T) -> HTTPResponse {
        let data = (try? JSONEncoder().encode(encodable)) ?? Data("{}".utf8)
        return HTTPResponse(statusCode: statusCode, reason: reasonPhrase(statusCode), body: data)
    }

    func serialized() -> Data {
        var response = Data()
        response.append("HTTP/1.1 \(statusCode) \(reason)\r\n".data(using: .utf8)!)
        response.append("Content-Type: application/json; charset=utf-8\r\n".data(using: .utf8)!)
        response.append("Cache-Control: no-store\r\n".data(using: .utf8)!)
        response.append("Content-Length: \(body.count + 1)\r\n".data(using: .utf8)!)
        response.append("Connection: close\r\n\r\n".data(using: .utf8)!)
        response.append(body)
        response.append(Data("\n".utf8))
        return response
    }

    private static func reasonPhrase(_ statusCode: Int) -> String {
        switch statusCode {
        case 200:
            return "OK"
        case 202:
            return "Accepted"
        case 400:
            return "Bad Request"
        case 408:
            return "Request Timeout"
        case 401:
            return "Unauthorized"
        case 404:
            return "Not Found"
        case 413:
            return "Payload Too Large"
        case 415:
            return "Unsupported Media Type"
        case 500:
            return "Internal Server Error"
        case 503:
            return "Service Unavailable"
        default:
            return "Internal Server Error"
        }
    }
}

final class ConnectionLimiter {
    private let maximumCount: Int
    private let lock = NSLock()
    private var count = 0

    init(maximumCount: Int) {
        precondition(maximumCount > 0)
        self.maximumCount = maximumCount
    }

    var activeCount: Int {
        lock.withLock { count }
    }

    func tryAcquire() -> Bool {
        lock.withLock {
            guard count < maximumCount else {
                return false
            }
            count += 1
            return true
        }
    }

    func release() {
        lock.withLock {
            precondition(count > 0)
            count -= 1
        }
    }
}
