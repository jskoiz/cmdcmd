import Darwin
import Foundation

final class RelayHTTPServer {
    private let settingsProvider: () -> RelaySettings
    private let statusStore: DeliveryStatusStore
    private let eventHandler: (RelayEvent) -> Void
    private let maxBodyBytes = 12_500_000
    private let acceptQueue = DispatchQueue(label: "app.cmdcmd.relay.http.accept", qos: .userInitiated)
    private let connectionQueue = DispatchQueue(label: "app.cmdcmd.relay.http.connection", qos: .userInitiated, attributes: .concurrent)
    private var listenSocket: Int32 = -1
    private var isStopping = false

    init(
        settingsProvider: @escaping () -> RelaySettings,
        statusStore: DeliveryStatusStore,
        eventHandler: @escaping (RelayEvent) -> Void
    ) {
        self.settingsProvider = settingsProvider
        self.statusStore = statusStore
        self.eventHandler = eventHandler
    }

    func start() throws {
        let settings = settingsProvider()
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

            connectionQueue.async { [weak self] in
                self?.handleConnection(clientFD)
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
            writeResponse(.json(statusCode: error.statusCode, body: ["error": error.localizedDescription]), to: clientFD)
        } catch {
            writeResponse(.json(statusCode: 502, body: ["error": error.localizedDescription]), to: clientFD)
        }
    }

    private func handle(_ request: HTTPRequest) throws -> HTTPResponse {
        if request.method == "GET", request.path == "/healthz" {
            let settings = settingsProvider()
            let accessibility = settings.deliveryMode == .codex
                ? (DesktopDelivery.accessibilityTrusted(prompt: false) ? "granted" : "required")
                : "not-required"
            return .json(
                statusCode: 200,
                body: [
                    "relay": "cmdcmd-native",
                    "status": "ok",
                    "deliveryMode": settings.deliveryMode.rawValue,
                    "accessibility": accessibility,
                    "pid": String(ProcessInfo.processInfo.processIdentifier),
                    "executablePath": Bundle.main.executablePath ?? CommandLine.arguments[0],
                    "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                    "bundleVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
                ]
            )
        }

        let settings = settingsProvider()
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

        DispatchQueue.global(qos: .userInitiated).async { [statusStore, eventHandler] in
            statusStore.delivering(captureId: capture.captureId, deliveryMode: settings.deliveryMode)
            eventHandler(.delivering(capture.captureId))
            do {
                switch settings.deliveryMode {
                case .codex:
                    try DesktopDelivery.deliver(capture: capture, stored: stored, settings: settings)
                case .reviewInbox:
                    try ReviewInboxDelivery.deliver(capture: capture, stored: stored, settings: settings)
                }
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
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        var expectedBodyLength: Int?
        var headerEndIndex: Data.Index?

        while true {
            let count = Darwin.recv(clientFD, &buffer, buffer.count, 0)
            if count < 0 {
                throw RelayHTTPError.badRequest("Could not read request.")
            }
            if count == 0 {
                break
            }

            data.append(buffer, count: count)
            if data.count > maxBodyBytes + 16_384 {
                throw RelayHTTPError.payloadTooLarge
            }

            if headerEndIndex == nil, let range = data.range(of: Data([13, 10, 13, 10])) {
                headerEndIndex = range.upperBound
                let headerData = data[..<range.lowerBound]
                let headerText = String(decoding: headerData, as: UTF8.self)
                expectedBodyLength = HTTPRequest.contentLength(from: headerText)
            }

            if let headerEndIndex, let expectedBodyLength,
               data.count >= headerEndIndex + expectedBodyLength {
                break
            }
        }

        guard let headerEndIndex else {
            throw RelayHTTPError.badRequest("Malformed HTTP request.")
        }

        let headerData = data[..<(headerEndIndex - 4)]
        let headerText = String(decoding: headerData, as: UTF8.self)
        let body = data[headerEndIndex...]
        let request = try HTTPRequest(headerText: headerText, body: Data(body.prefix(expectedBodyLength ?? 0)))
        if request.body.count > maxBodyBytes {
            throw RelayHTTPError.payloadTooLarge
        }
        return request
    }

    private func writeResponse(_ response: HTTPResponse, to clientFD: Int32) {
        let data = response.serialized()
        data.withUnsafeBytes { pointer in
            guard let baseAddress = pointer.baseAddress else {
                return
            }
            _ = Darwin.send(clientFD, baseAddress, data.count, 0)
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
}

enum RelayEvent {
    case ready(String)
    case accepted(String)
    case delivering(String)
    case delivered(String)
    case failed(String)
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    init(headerText: String, body: Data) throws {
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw RelayHTTPError.badRequest("Malformed HTTP request.")
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw RelayHTTPError.badRequest("Malformed HTTP request line.")
        }

        self.method = requestParts[0].uppercased()
        self.path = requestParts[1]
        self.headers = Dictionary(
            uniqueKeysWithValues: lines.dropFirst().compactMap { line in
                guard let separator = line.firstIndex(of: ":") else {
                    return nil
                }
                let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                return (key, value)
            }
        )
        self.body = body
    }

    static func contentLength(from headerText: String) -> Int {
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key == "content-length" {
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                return Int(value) ?? 0
            }
        }
        return 0
    }
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
        case 401:
            return "Unauthorized"
        case 404:
            return "Not Found"
        case 413:
            return "Payload Too Large"
        case 415:
            return "Unsupported Media Type"
        default:
            return "Bad Gateway"
        }
    }
}
