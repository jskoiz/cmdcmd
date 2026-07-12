import Foundation
import XCTest
@testable import CmdCmdRelayApp

final class CapturePayloadTests: XCTestCase {
    func testMalformedJSONReturnsStableBadRequest() {
        assertBadRequest(
            Data("not-json".utf8),
            message: "Request body must be valid JSON."
        )
    }

    func testMissingFieldReturnsStableBadRequest() throws {
        var object = RelayTestFixtures.payloadObject()
        object.removeValue(forKey: "source")

        assertBadRequest(
            try JSONSerialization.data(withJSONObject: object),
            message: "Request body does not match the capture schema."
        )
    }

    func testWrongFieldTypeReturnsStableBadRequest() throws {
        var object = RelayTestFixtures.payloadObject()
        object["imageFilename"] = 42

        assertBadRequest(
            try JSONSerialization.data(withJSONObject: object),
            message: "Request body does not match the capture schema."
        )
    }

    private func assertBadRequest(
        _ data: Data,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try CapturePayload.decode(from: data), file: file, line: line) { error in
            XCTAssertEqual((error as? RelayHTTPError)?.statusCode, 400, file: file, line: line)
            XCTAssertEqual(error.localizedDescription, message, file: file, line: line)
        }
    }
}
