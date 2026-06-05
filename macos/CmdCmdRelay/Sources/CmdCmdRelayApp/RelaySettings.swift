import Foundation
import Security

struct RelaySettings: Codable, Equatable {
    var token: String
    var host: String
    var port: Int
    var inboxDirectory: String
    var codexBundleIdentifier: String
    var openImageInViewer: Bool
    var viewerBundleIdentifier: String
    var closeViewerWindow: Bool
    var pasteDelayMilliseconds: Int

    static var defaultSettings: RelaySettings {
        RelaySettings(
            token: TokenGenerator.randomToken(),
            host: "127.0.0.1",
            port: 8787,
            inboxDirectory: FileLocations.defaultInboxDirectory.path,
            codexBundleIdentifier: "com.openai.codex",
            openImageInViewer: true,
            viewerBundleIdentifier: "com.apple.Preview",
            closeViewerWindow: true,
            pasteDelayMilliseconds: 400
        )
    }

    var listensOnPrivateNetwork: Bool {
        host == "0.0.0.0"
    }

    var localEndpoint: URL {
        URL(string: "http://127.0.0.1:\(port)/v1/captures")!
    }

    var phoneEndpoint: URL {
        let hostName = listensOnPrivateNetwork
            ? (NetworkIdentity.privateIPv4Address() ?? "127.0.0.1")
            : "127.0.0.1"
        return URL(string: "http://\(hostName):\(port)/v1/captures")!
    }

    var pairingURL: URL {
        var components = URLComponents()
        components.scheme = "cmdcmd"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "endpoint", value: phoneEndpoint.absoluteString),
            URLQueryItem(name: "token", value: token)
        ]
        return components.url!
    }
}

enum FileLocations {
    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent("cmdcmd-relay", isDirectory: true)
    }

    static var defaultInboxDirectory: URL {
        appSupportDirectory.appendingPathComponent("inbox", isDirectory: true)
    }

    static var settingsFile: URL {
        appSupportDirectory.appendingPathComponent("config.json")
    }
}

enum RelaySettingsStore {
    static func load() -> RelaySettings {
        let url = FileLocations.settingsFile
        guard let data = try? Data(contentsOf: url) else {
            let settings = RelaySettings.defaultSettings
            try? save(settings)
            return settings
        }

        do {
            return try JSONDecoder().decode(RelaySettings.self, from: data)
        } catch {
            let settings = RelaySettings.defaultSettings
            try? save(settings)
            return settings
        }
    }

    static func save(_ settings: RelaySettings) throws {
        try FileManager.default.createDirectory(
            at: FileLocations.appSupportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: FileLocations.settingsFile, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: FileLocations.settingsFile.path
        )
    }
}

enum TokenGenerator {
    static func randomToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }

        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

