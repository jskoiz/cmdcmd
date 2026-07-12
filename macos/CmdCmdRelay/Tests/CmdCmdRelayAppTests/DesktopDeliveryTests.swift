import CoreGraphics
import Foundation
import XCTest
@testable import CmdCmdRelayApp

final class DesktopDeliveryTests: XCTestCase {
    func testAttachmentTextKeepsContextLiteral() throws {
        var capture = try RelayTestFixtures.capture()
        capture.context = "Compare A < B & C > D"
        capture.recognizedText = ""

        let text = try XCTUnwrap(DesktopDelivery.attachmentText(capture: capture))

        XCTAssertTrue(text.contains("Context:\nCompare A < B & C > D"))
        XCTAssertFalse(text.contains("&lt;"))
        XCTAssertFalse(text.contains("&amp;"))
    }

    func testAttachmentTextFiltersAndDeduplicatesNoisyOCR() throws {
        var capture = try RelayTestFixtures.capture()
        capture.context = ""
        capture.screenshotContext.ocrEnabled = true
        capture.screenshotContext.ocrLineCount = 16
        capture.screenshotContext.ocrCharacterCount = 140
        capture.recognizedText = [
            "4 Phone",
            "8:04",
            "+",
            "*",
            "•••",
            "3:19",
            "• | 5 5",
            "26 + H",
            "•••",
            "cmd+cmd",
            "& OCR ready",
            "U Thread hint",
            ") Sending to Codex",
            "* Sending...",
            "Sending to Codex",
            "Sending..."
        ].joined(separator: "\n")

        let text = try XCTUnwrap(DesktopDelivery.attachmentText(capture: capture))

        XCTAssertTrue(text.contains("OCR: 5 useful lines, 57 characters"))
        XCTAssertTrue(text.hasSuffix(
            "OCR text:\ncmd+cmd\nOCR ready\nThread hint\nSending to Codex\nSending..."
        ))
    }

    func testAttachmentTextOmitsLowSignalOCR() throws {
        var capture = try RelayTestFixtures.capture()
        capture.context = ""
        capture.screenshotContext.ocrEnabled = true
        capture.screenshotContext.ocrLineCount = 5
        capture.screenshotContext.ocrCharacterCount = 18
        capture.recognizedText = ["8:04", "+", "•••", "3:19", "5 5"].joined(separator: "\n")

        let text = try XCTUnwrap(DesktopDelivery.attachmentText(capture: capture))

        XCTAssertTrue(text.contains("OCR: noisy text omitted"))
        XCTAssertFalse(text.contains("OCR text:"))
    }

    func testAttachmentPastePathsKeepsImageAndContextTogether() {
        XCTAssertEqual(
            DesktopDelivery.attachmentPastePaths(
                imagePath: "/tmp/capture.png",
                contextPath: "/tmp/capture.txt"
            ),
            ["/tmp/capture.png", "/tmp/capture.txt"]
        )
    }

    func testAttachmentPastePathsOmitsMissingContext() {
        XCTAssertEqual(
            DesktopDelivery.attachmentPastePaths(
                imagePath: "/tmp/capture.png",
                contextPath: nil
            ),
            ["/tmp/capture.png"]
        )
    }

    func testPasteboardFileURLsRequireExistingFileAttachments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmdcmd-relay-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("capture.png")
        let contextURL = directory.appendingPathComponent("capture.txt")
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: imageURL)
        try "Screenshot context\n".write(to: contextURL, atomically: true, encoding: .utf8)

        let urls = try DesktopDelivery.pasteboardFileURLs(for: [imageURL.path, contextURL.path])

        XCTAssertEqual(urls.map { ($0 as URL).path }, [imageURL.path, contextURL.path])
        XCTAssertTrue(urls.allSatisfy { ($0 as URL).isFileURL })
    }

    func testPasteboardFileURLsRejectMissingAttachments() throws {
        let missingPath = "/tmp/cmdcmd-relay-missing-\(UUID().uuidString).txt"

        XCTAssertThrowsError(try DesktopDelivery.pasteboardFileURLs(for: [missingPath])) { error in
            XCTAssertEqual(error.localizedDescription, "Could not find attachment: \(missingPath).")
        }
    }

    func testPasteFailsWhenKeyboardEventCannotBeCreated() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))

        XCTAssertThrowsError(
            try DesktopDelivery.postPaste(source, eventFactory: { _, _, _ in nil })
        ) { error in
            XCTAssertEqual((error as? RelayHTTPError)?.statusCode, 500)
            XCTAssertEqual(error.localizedDescription, "Could not create keyboard event.")
        }
    }
}
