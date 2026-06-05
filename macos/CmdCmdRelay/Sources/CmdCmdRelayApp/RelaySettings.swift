import Foundation
import Security

struct RelaySettings: Codable, Equatable {
    var token: String
    var host: String
    var port: Int
    var inboxDirectory: String
    var codexBundleIdentifier: String
    var deliveryMode: RelayDeliveryMode
    var pasteDelayMilliseconds: Int

    enum CodingKeys: String, CodingKey {
        case token
        case host
        case port
        case inboxDirectory
        case codexBundleIdentifier
        case deliveryMode
        case pasteDelayMilliseconds
    }

    static var defaultSettings: RelaySettings {
        RelaySettings(
            token: TokenGenerator.randomToken(),
            host: "127.0.0.1",
            port: 8787,
            inboxDirectory: FileLocations.defaultInboxDirectory.path,
            codexBundleIdentifier: "com.openai.codex",
            deliveryMode: .codex,
            pasteDelayMilliseconds: 400
        )
    }

    init(
        token: String,
        host: String,
        port: Int,
        inboxDirectory: String,
        codexBundleIdentifier: String,
        deliveryMode: RelayDeliveryMode,
        pasteDelayMilliseconds: Int
    ) {
        self.token = token
        self.host = host
        self.port = port
        self.inboxDirectory = inboxDirectory
        self.codexBundleIdentifier = codexBundleIdentifier
        self.deliveryMode = deliveryMode
        self.pasteDelayMilliseconds = pasteDelayMilliseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        inboxDirectory = try container.decode(String.self, forKey: .inboxDirectory)
        codexBundleIdentifier = try container.decode(String.self, forKey: .codexBundleIdentifier)
        deliveryMode = try container.decodeIfPresent(RelayDeliveryMode.self, forKey: .deliveryMode) ?? .codex
        pasteDelayMilliseconds = try container.decode(Int.self, forKey: .pasteDelayMilliseconds)
    }

    var listensOnPrivateNetwork: Bool {
        host == "0.0.0.0"
    }

    var localEndpoint: URL {
        URL(string: "http://127.0.0.1:\(port)/v1/captures")!
    }

    var phoneEndpoint: URL {
        URL(string: "http://\(phoneEndpointHost):\(port)/v1/captures")!
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

    var compactPairingURL: URL {
        var components = URLComponents()
        components.scheme = "cmdcmd"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "e", value: "\(phoneEndpointHost):\(port)"),
            URLQueryItem(name: "t", value: token)
        ]
        return components.url!
    }

    private var phoneEndpointHost: String {
        listensOnPrivateNetwork
            ? (NetworkIdentity.privateIPv4Address() ?? "127.0.0.1")
            : "127.0.0.1"
    }
}

enum RelayDeliveryMode: String, Codable, Equatable {
    case codex
    case reviewInbox
}

enum FileLocations {
    static var appSupportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CMDCMD_RELAY_APP_SUPPORT_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

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
