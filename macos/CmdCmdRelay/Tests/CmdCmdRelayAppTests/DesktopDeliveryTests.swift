import Foundation
import XCTest
@testable import CmdCmdRelayApp

final class DesktopDeliveryTests: XCTestCase {
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
}
