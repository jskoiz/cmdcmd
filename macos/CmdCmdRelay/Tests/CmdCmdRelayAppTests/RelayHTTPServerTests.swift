import Foundation
import XCTest
@testable import CmdCmdRelayApp

final class RelayHTTPServerTests: XCTestCase {
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
}
