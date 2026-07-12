import Foundation
import XCTest
@testable import CmdCmdRelayApp

final class ReviewInboxDeliveryTests: XCTestCase {
    func testCorruptManifestIsPreservedWithoutWritingNewAsset() throws {
        let inboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmdcmd-review-inbox-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: inboxURL) }
        let settings = RelayTestFixtures.settings(
            inboxDirectory: inboxURL.path,
            deliveryMode: .reviewInbox
        )
        let reviewURL = inboxURL.appendingPathComponent("review-inbox", isDirectory: true)
        let capturesURL = reviewURL.appendingPathComponent("captures", isDirectory: true)
        try FileManager.default.createDirectory(at: capturesURL, withIntermediateDirectories: true)
        let manifestURL = reviewURL.appendingPathComponent("captures.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: manifestURL)
        let existingAssetURL = capturesURL.appendingPathComponent("existing.png")
        try Data([0x01]).write(to: existingAssetURL)
        let capture = try RelayTestFixtures.capture()
        let newAssetURL = capturesURL.appendingPathComponent("\(capture.captureId).png")

        XCTAssertThrowsError(
            try ReviewInboxDelivery.deliver(
                capture: capture,
                stored: StoredCapture(
                    imagePath: "/tmp/original-\(capture.captureId).png",
                    metadataPath: "/tmp/original-\(capture.captureId).json"
                ),
                settings: settings,
                openInboxHandler: { _ in }
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Review inbox history is unreadable. The existing history was preserved."
            )
        }
        XCTAssertEqual(try Data(contentsOf: manifestURL), corruptData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingAssetURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newAssetURL.path))
    }

    func testReviewHistoryDeletesOnlyEvictedManagedAssets() throws {
        let inboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmdcmd-review-inbox-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: inboxURL) }
        let settings = RelayTestFixtures.settings(
            inboxDirectory: inboxURL.path,
            deliveryMode: .reviewInbox
        )
        let capturesURL = inboxURL
            .appendingPathComponent("review-inbox", isDirectory: true)
            .appendingPathComponent("captures", isDirectory: true)
        try FileManager.default.createDirectory(at: capturesURL, withIntermediateDirectories: true)
        let unrelatedURL = capturesURL.appendingPathComponent("keep.txt")
        try "keep".write(to: unrelatedURL, atomically: true, encoding: .utf8)

        var captureIds: [String] = []
        for _ in 0..<51 {
            let captureId = UUID().uuidString
            captureIds.append(captureId)
            let capture = try RelayTestFixtures.capture(captureId: captureId)
            try ReviewInboxDelivery.deliver(
                capture: capture,
                stored: StoredCapture(
                    imagePath: "/tmp/original-\(captureId).png",
                    metadataPath: "/tmp/original-\(captureId).json"
                ),
                settings: settings,
                openInboxHandler: { _ in }
            )
        }

        let assetNames = try FileManager.default.contentsOfDirectory(atPath: capturesURL.path)
        XCTAssertEqual(assetNames.filter { $0.hasSuffix(".png") }.count, 50)
        XCTAssertFalse(assetNames.contains("\(captureIds[0]).png"))
        XCTAssertTrue(assetNames.contains("\(captureIds[50]).png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))

        let manifestURL = inboxURL
            .appendingPathComponent("review-inbox", isDirectory: true)
            .appendingPathComponent("captures.json")
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [[String: Any]]
        )
        XCTAssertEqual(manifest.count, 50)
        XCTAssertEqual(manifest.first?["captureId"] as? String, captureIds[50])
        XCTAssertFalse(manifest.contains { $0["captureId"] as? String == captureIds[0] })
    }
}
