import Foundation
import XCTest
@testable import CmdCmdRelayApp

final class RelaySettingsTests: XCTestCase {
    func testMissingSettingsAreCreatedOnceAndReloaded() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("config.json")

        let created = try RelaySettingsStore.loadOrCreate(from: settingsURL)
        let firstData = try Data(contentsOf: settingsURL)
        let reloaded = try RelaySettingsStore.loadOrCreate(from: settingsURL)

        XCTAssertEqual(reloaded, created)
        XCTAssertEqual(try Data(contentsOf: settingsURL), firstData)
    }

    func testCorruptSettingsArePreservedAndReported() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("config.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: settingsURL)

        XCTAssertThrowsError(try RelaySettingsStore.loadOrCreate(from: settingsURL))
        XCTAssertEqual(try Data(contentsOf: settingsURL), corruptData)
    }

    func testUnreadableSettingsLocationIsPreservedAndReported() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("config.json", isDirectory: true)
        try FileManager.default.createDirectory(at: settingsURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(try RelaySettingsStore.loadOrCreate(from: settingsURL))

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCurrentSchemaRequiresDeliveryMode() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("config.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(RelaySettings.defaultSettings)) as? [String: Any]
        )
        object.removeValue(forKey: "deliveryMode")
        let originalData = try JSONSerialization.data(withJSONObject: object)
        try originalData.write(to: settingsURL)

        XCTAssertThrowsError(try RelaySettingsStore.loadOrCreate(from: settingsURL))
        XCTAssertEqual(try Data(contentsOf: settingsURL), originalData)
    }

    func testValidationRejectsEmptyAndOutOfRangeFields() {
        assertInvalid(settings(token: ""))
        assertInvalid(settings(host: "  "))
        assertInvalid(settings(inboxDirectory: ""))
        assertInvalid(settings(codexBundleIdentifier: ""))
        assertInvalid(settings(port: 0))
        assertInvalid(settings(port: 65_536))
        assertInvalid(settings(pasteDelayMilliseconds: -1))
        assertInvalid(settings(pasteDelayMilliseconds: RelaySettings.maximumPasteDelayMilliseconds + 1))
    }

    private func settings(
        token: String = "token",
        host: String = "127.0.0.1",
        port: Int = 8787,
        inboxDirectory: String = "/tmp/cmdcmd-relay-tests",
        codexBundleIdentifier: String = "com.openai.codex",
        pasteDelayMilliseconds: Int = 400
    ) -> RelaySettings {
        RelaySettings(
            token: token,
            host: host,
            port: port,
            inboxDirectory: inboxDirectory,
            codexBundleIdentifier: codexBundleIdentifier,
            deliveryMode: .codex,
            pasteDelayMilliseconds: pasteDelayMilliseconds
        )
    }

    private func assertInvalid(_ settings: RelaySettings, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try settings.validated(), file: file, line: line)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmdcmd-relay-settings-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
