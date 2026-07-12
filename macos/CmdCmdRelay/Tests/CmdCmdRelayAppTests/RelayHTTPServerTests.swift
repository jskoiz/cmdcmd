import Darwin
import Foundation
import XCTest
@testable import CmdCmdRelayApp

final class RelayHTTPServerTests: XCTestCase {
    func testDripFedRequestCannotOutliveAbsoluteDeadline() throws {
        let relay = try startRelay(requestTimeout: 0.3)
        defer { relay.stop() }
        let clientFD = try connectRawClient(to: relay.port)
        defer { Darwin.close(clientFD) }
        let startedAt = Date()

        try sendRaw("G", to: clientFD)
        usleep(200_000)
        try sendRaw("E", to: clientFD)
        let response = try receiveRawResponse(from: clientFD)

        XCTAssertTrue(response.hasPrefix("HTTP/1.1 408 Request Timeout"))
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.44)
    }

    func testConcurrentConnectionLimitRejectsExcessBeforeSpawningWorker() throws {
        let relay = try startRelay(requestTimeout: 1, maximumConcurrentConnections: 1)
        defer { relay.stop() }
        let heldClientFD = try connectRawClient(to: relay.port)
        defer { Darwin.close(heldClientFD) }
        try sendRaw("G", to: heldClientFD)
        XCTAssertTrue(waitForActiveConnectionCount(1, relay: relay))

        let rejectedClientFD = try connectRawClient(to: relay.port)
        defer { Darwin.close(rejectedClientFD) }
        try sendRaw("GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n", to: rejectedClientFD)
        let response: String?
        do {
            response = try receiveRawResponse(from: rejectedClientFD)
        } catch let error as POSIXError where error.code == .ECONNRESET {
            response = nil
        }

        if let response {
            XCTAssertTrue(response.hasPrefix("HTTP/1.1 503 Service Unavailable"))
        }
        XCTAssertEqual(relay.server.activeConnectionCount, 1)
    }

    func testHealthResponseIsMinimalWithoutAuthorization() async throws {
        let relay = try startRelay()
        defer { relay.stop() }

        let response = try await sendRequest(to: relay, method: "GET", path: "/healthz")

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.json as? [String: String], ["relay": "cmdcmd-native", "status": "ok"])
    }

    func testAuthorizedCapturePersistsAndTransitionsToDelivered() async throws {
        let delivered = expectation(description: "capture delivered")
        let relay = try startRelay(deliveryHandler: { _, _, _ in delivered.fulfill() })
        defer { relay.stop() }
        let captureId = UUID().uuidString
        let body = try RelayTestFixtures.payloadData(captureId: captureId)

        let unauthorized = try await sendRequest(
            to: relay,
            method: "POST",
            path: "/v1/captures",
            body: body
        )
        XCTAssertEqual(unauthorized.statusCode, 401)

        let accepted = try await sendRequest(
            to: relay,
            method: "POST",
            path: "/v1/captures",
            token: relay.settings.token,
            body: body
        )
        XCTAssertEqual(accepted.statusCode, 202)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(accepted.json["imagePath"] as? String)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(accepted.json["metadataPath"] as? String)))

        await fulfillment(of: [delivered], timeout: 2)
        let status = try await waitForStatus("delivered", captureId: captureId, relay: relay)
        XCTAssertEqual(status.json["deliveryLane"] as? String, "desktop-attachment")
        XCTAssertEqual(
            relay.events.values,
            ["accepted:\(captureId)", "delivering:\(captureId)", "delivered:\(captureId)"]
        )
    }

    func testMalformedPayloadsReturnSanitizedBadRequests() async throws {
        let relay = try startRelay()
        defer { relay.stop() }
        var missingField = RelayTestFixtures.payloadObject()
        missingField.removeValue(forKey: "source")
        var wrongType = RelayTestFixtures.payloadObject()
        wrongType["imageFilename"] = 42
        let cases: [(Data, String)] = [
            (Data("not-json".utf8), "Request body must be valid JSON."),
            (
                try JSONSerialization.data(withJSONObject: missingField),
                "Request body does not match the capture schema."
            ),
            (
                try JSONSerialization.data(withJSONObject: wrongType),
                "Request body does not match the capture schema."
            )
        ]

        for (body, expectedMessage) in cases {
            let response = try await sendRequest(
                to: relay,
                method: "POST",
                path: "/v1/captures",
                token: relay.settings.token,
                body: body
            )
            XCTAssertEqual(response.statusCode, 400)
            XCTAssertEqual(response.json["error"] as? String, expectedMessage)
        }
    }

    func testDeliveryFailuresCannotBecomeDelivered() async throws {
        let relay = try startRelay(deliveryHandler: { _, _, _ in
            throw RelayHTTPError.server("Could not create keyboard event.")
        })
        defer { relay.stop() }
        let captureId = UUID().uuidString

        let accepted = try await sendRequest(
            to: relay,
            method: "POST",
            path: "/v1/captures",
            token: relay.settings.token,
            body: try RelayTestFixtures.payloadData(captureId: captureId)
        )
        XCTAssertEqual(accepted.statusCode, 202)

        let status = try await waitForStatus("failed", captureId: captureId, relay: relay)
        XCTAssertEqual(status.json["status"] as? String, "failed")
        XCTAssertFalse(relay.events.values.contains("delivered:\(captureId)"))
    }

    func testDeliveryQueuePreservesCaptureAcceptanceOrder() async throws {
        let deliveries = LockedValues<String>()
        let completed = expectation(description: "queued deliveries")
        completed.expectedFulfillmentCount = 2
        let relay = try startRelay(deliveryHandler: { capture, _, _ in
            deliveries.append(capture.captureId)
            completed.fulfill()
        })
        defer { relay.stop() }
        let captureIds = [UUID().uuidString, UUID().uuidString]

        for captureId in captureIds {
            let response = try await sendRequest(
                to: relay,
                method: "POST",
                path: "/v1/captures",
                token: relay.settings.token,
                body: try RelayTestFixtures.payloadData(captureId: captureId)
            )
            XCTAssertEqual(response.statusCode, 202)
        }

        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(deliveries.values, captureIds)
    }

    func testRejectsDuplicateCaseFoldedHeaders() {
        assertStatus(400, headerText: "GET /healthz HTTP/1.1\r\nX-Test: one\r\nx-test: two")
    }

    func testRejectsDuplicateContentLength() {
        assertStatus(
            400,
            headerText: "POST /v1/captures HTTP/1.1\r\nContent-Length: 2\r\ncontent-length: 2",
            body: Data("{}".utf8)
        )
    }

    func testRejectsInvalidContentLengths() {
        for value in ["-1", "+1", "1.0", "abc", "999999999999999999999999999999999999"] {
            assertStatus(
                400,
                headerText: "POST /v1/captures HTTP/1.1\r\nContent-Length: \(value)"
            )
        }
    }

    func testRejectsOversizedContentLength() {
        assertStatus(
            413,
            headerText: "POST /v1/captures HTTP/1.1\r\nContent-Length: 11",
            maxBodyBytes: 10
        )
    }

    func testRejectsMissingContentLengthOnPost() {
        assertStatus(400, headerText: "POST /v1/captures HTTP/1.1\r\nContent-Type: application/json")
    }

    func testRejectsTransferEncoding() {
        assertStatus(400, headerText: "POST /v1/captures HTTP/1.1\r\nTransfer-Encoding: chunked")
    }

    func testRejectsMalformedHeaderAndEmptyName() {
        assertStatus(400, headerText: "GET /healthz HTTP/1.1\r\nMalformed")
        assertStatus(400, headerText: "GET /healthz HTTP/1.1\r\n: value")
    }

    func testParsesValidGetWithoutBody() throws {
        let request = try HTTPRequest(headerText: "GET /healthz HTTP/1.1\r\nHost: 127.0.0.1", body: Data())

        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/healthz")
        XCTAssertEqual(request.headers["host"], "127.0.0.1")
        XCTAssertTrue(request.body.isEmpty)
    }

    func testParsesValidJSONPost() throws {
        let body = Data("{}".utf8)
        let request = try HTTPRequest(
            headerText: "POST /v1/captures HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2",
            body: body
        )

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/captures")
        XCTAssertEqual(request.headers["content-type"], "application/json")
        XCTAssertEqual(request.body, body)
    }

    private func assertStatus(
        _ expectedStatus: Int,
        headerText: String,
        body: Data = Data(),
        maxBodyBytes: Int = 12_500_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try HTTPRequest(headerText: headerText, body: body, maxBodyBytes: maxBodyBytes),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual((error as? RelayHTTPError)?.statusCode, expectedStatus, file: file, line: line)
        }
    }

    private func startRelay(
        requestTimeout: TimeInterval = 15,
        maximumConcurrentConnections: Int = 16,
        deliveryHandler: @escaping RelayHTTPServer.DeliveryHandler = { _, _, _ in }
    ) throws -> RunningRelay {
        let inboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmdcmd-http-server-tests-\(UUID().uuidString)", isDirectory: true)
        let settings = RelayTestFixtures.settings(inboxDirectory: inboxURL.path)
        let statusStore = DeliveryStatusStore()
        let events = RelayEventRecorder()
        let server = RelayHTTPServer(
            settingsProvider: { settings },
            statusStore: statusStore,
            eventHandler: { events.record($0) },
            deliveryHandler: deliveryHandler,
            requestTimeout: requestTimeout,
            maximumConcurrentConnections: maximumConcurrentConnections
        )
        try server.start()
        return RunningRelay(
            server: server,
            settings: settings,
            statusStore: statusStore,
            events: events,
            inboxURL: inboxURL,
            port: try XCTUnwrap(server.listeningPort)
        )
    }

    private func connectRawClient(to port: Int) throws -> Int32 {
        let clientFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard clientFD >= 0 else {
            throw POSIXError(.ENOTSOCK)
        }

        var noSigPipe: Int32 = 1
        setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var receiveTimeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(clientFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(clientFD)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECONNREFUSED)
        }
        return clientFD
    }

    private func sendRaw(_ string: String, to clientFD: Int32) throws {
        let data = Data(string.utf8)
        try data.withUnsafeBytes { pointer in
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
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPIPE)
                }
                sent += count
            }
        }
    }

    private func receiveRawResponse(from clientFD: Int32) throws -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.recv(clientFD, &buffer, buffer.count, 0)
            if count > 0 {
                data.append(buffer, count: count)
                continue
            }
            if count == 0 {
                break
            }
            if errno == EINTR {
                continue
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func waitForActiveConnectionCount(_ count: Int, relay: RunningRelay) -> Bool {
        for _ in 0..<200 {
            if relay.server.activeConnectionCount == count {
                return true
            }
            usleep(1_000)
        }
        return false
    }

    private func sendRequest(
        to relay: RunningRelay,
        method: String,
        path: String,
        token: String? = nil,
        body: Data? = nil
    ) async throws -> TestHTTPResponse {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(relay.port)\(path)")!)
        request.httpMethod = method
        request.timeoutInterval = 3
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return TestHTTPResponse(statusCode: httpResponse.statusCode, json: json)
    }

    private func waitForStatus(
        _ expectedStatus: String,
        captureId: String,
        relay: RunningRelay
    ) async throws -> TestHTTPResponse {
        var latest: TestHTTPResponse?
        for _ in 0..<100 {
            let response = try await sendRequest(
                to: relay,
                method: "GET",
                path: "/v1/captures/\(captureId)/status",
                token: relay.settings.token
            )
            latest = response
            if response.json["status"] as? String == expectedStatus {
                return response
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for status \(expectedStatus).")
        return try XCTUnwrap(latest, "Timed out waiting for status \(expectedStatus).")
    }
}

private struct TestHTTPResponse {
    var statusCode: Int
    var json: [String: Any]
}

private final class RunningRelay {
    let server: RelayHTTPServer
    let settings: RelaySettings
    let statusStore: DeliveryStatusStore
    let events: RelayEventRecorder
    let inboxURL: URL
    let port: Int

    init(
        server: RelayHTTPServer,
        settings: RelaySettings,
        statusStore: DeliveryStatusStore,
        events: RelayEventRecorder,
        inboxURL: URL,
        port: Int
    ) {
        self.server = server
        self.settings = settings
        self.statusStore = statusStore
        self.events = events
        self.inboxURL = inboxURL
        self.port = port
    }

    func stop() {
        server.stop()
        if FileManager.default.fileExists(atPath: inboxURL.path) {
            try? FileManager.default.removeItem(at: inboxURL)
        }
    }
}

private final class RelayEventRecorder {
    private let storage = LockedValues<String>()

    var values: [String] { storage.values }

    func record(_ event: RelayEvent) {
        switch event {
        case .ready(let message):
            storage.append("ready:\(message)")
        case .accepted(let captureId):
            storage.append("accepted:\(captureId)")
        case .delivering(let captureId):
            storage.append("delivering:\(captureId)")
        case .delivered(let captureId):
            storage.append("delivered:\(captureId)")
        case .failed(let message):
            storage.append("failed:\(message)")
        }
    }
}

private final class LockedValues<Value> {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
