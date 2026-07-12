import Foundation
import Security

struct RelaySettings: Codable, Equatable {
    static let maximumPasteDelayMilliseconds = 60_000

    var token: String
    var host: String
    var port: Int
    var inboxDirectory: String
    var codexBundleIdentifier: String
    var deliveryMode: RelayDeliveryMode
    var pasteDelayMilliseconds: Int

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

    func validated() throws -> RelaySettings {
        try Self.requireNonempty(token, field: "token")
        try Self.requireNonempty(host, field: "host")
        try Self.requireNonempty(inboxDirectory, field: "inboxDirectory")
        try Self.requireNonempty(codexBundleIdentifier, field: "codexBundleIdentifier")
        guard (1...65_535).contains(port) else {
            throw RelaySettingsError.invalid("port must be an integer from 1 to 65535.")
        }
        guard (0...Self.maximumPasteDelayMilliseconds).contains(pasteDelayMilliseconds) else {
            throw RelaySettingsError.invalid(
                "pasteDelayMilliseconds must be between 0 and \(Self.maximumPasteDelayMilliseconds)."
            )
        }
        return self
    }

    private static func requireNonempty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelaySettingsError.invalid("\(field) must not be empty.")
        }
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

enum RelaySettingsError: Error, LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return "Invalid relay settings: \(message)"
        }
    }
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
    static func loadOrCreate(from url: URL = FileLocations.settingsFile) throws -> RelaySettings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let settings = RelaySettings.defaultSettings
            try save(settings, to: url)
            return settings
        }

        let data = try Data(contentsOf: url)
        let settings = try JSONDecoder().decode(RelaySettings.self, from: data)
        return try settings.validated()
    }

    static func save(_ settings: RelaySettings, to url: URL = FileLocations.settingsFile) throws {
        _ = try settings.validated()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
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
