import Foundation

enum CaptureSource: String, Codable, CaseIterable, Identifiable {
    case mainApp
    case shareExtension
    case shortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mainApp:
            "App"
        case .shareExtension:
            "Share"
        case .shortcut:
            "Shortcut"
        }
    }
}

enum CaptureStatus: String, Codable, CaseIterable, Identifiable {
    case needsEndpoint
    case sending
    case sent
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsEndpoint:
            "Needs endpoint"
        case .sending:
            "Sending"
        case .sent:
            "Sent"
        case .failed:
            "Failed"
        }
    }
}

struct CaptureRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var source: CaptureSource
    var sourceDetail: String
    var userNote: String
    var recognizedText: String
    var status: CaptureStatus
    var statusMessage: String
    var endpointHost: String?
    var imageFilename: String
    var thumbnailData: Data?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        source: CaptureSource,
        sourceDetail: String = "",
        userNote: String,
        recognizedText: String,
        status: CaptureStatus,
        statusMessage: String,
        endpointHost: String?,
        imageFilename: String,
        thumbnailData: Data?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.sourceDetail = sourceDetail
        self.userNote = userNote
        self.recognizedText = recognizedText
        self.status = status
        self.statusMessage = statusMessage
        self.endpointHost = endpointHost
        self.imageFilename = imageFilename
        self.thumbnailData = thumbnailData
    }
}

struct RelaySettings: Codable, Hashable {
    var endpoint: String
    var apiToken: String
    var defaultContext: String
    var includeRecognizedText: Bool

    static let empty = RelaySettings(
        endpoint: "",
        apiToken: "",
        defaultContext: "",
        includeRecognizedText: true
    )
}

struct PairingLink: Equatable {
    var endpoint: String
    var token: String

    static func parse(_ rawValue: String) -> PairingLink? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")

        guard let url = URL(string: normalized) else {
            return nil
        }

        return parse(url)
    }

    static func parse(_ url: URL) -> PairingLink? {
        guard url.scheme == "cmdcmd",
              url.host() == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let endpoint = queryValue(["endpoint"], in: components)
            ?? endpointFromCompactValue(queryValue(["e"], in: components))
            ?? ""
        let token = queryValue(["token", "t"], in: components) ?? ""

        guard !endpoint.isEmpty, !token.isEmpty else {
            return nil
        }

        return PairingLink(endpoint: endpoint, token: token)
    }

    private static func queryValue(_ names: [String], in components: URLComponents) -> String? {
        components.queryItems?
            .first(where: { names.contains($0.name) })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func endpointFromCompactValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        if let url = URL(string: value),
           let scheme = url.scheme,
           ["http", "https"].contains(scheme),
           url.host() != nil {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if components?.path.isEmpty == true || components?.path == "/" {
                components?.path = "/v1/captures"
            }
            return components?.url?.absoluteString
        }

        return "http://\(value)/v1/captures"
    }
}

enum FailureSettingsDestination {
    case relay
    case systemApp
}

enum CaptureFailurePresentation {
    static func relayReachabilityMessage(endpoint: String) -> String {
        guard let host = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host(),
              !host.isEmpty else {
            return "Could not reach the relay. Check the endpoint, Wi-Fi, and relay app, then try again."
        }

        return "Could not reach the relay at \(host). Make sure this iPhone and Mac are on the same network and the relay is running, then try again."
    }

    static func settingsDestination(for message: String?) -> FailureSettingsDestination {
        guard let message else {
            return .relay
        }

        let normalizedMessage = message
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if normalizedMessage.contains("local network") {
            return .systemApp
        }

        return .relay
    }

    static func settingsActionTitle(for message: String?) -> String {
        switch settingsDestination(for: message) {
        case .relay:
            return "Open Relay Settings"
        case .systemApp:
            return "Show Fix"
        }
    }
}

struct CaptureImageMetadata: Codable, Hashable {
    var capturedAt: Date?
    var pixelWidth: Int?
    var pixelHeight: Int?

    static let empty = CaptureImageMetadata()
}

struct OCRReport: Codable, Hashable {
    var text: String
    var durationMs: Int
    var lineCount: Int
    var characterCount: Int
    var timedOut: Bool
    var averageConfidence: Double?

    static let skipped = OCRReport(
        text: "",
        durationMs: 0,
        lineCount: 0,
        characterCount: 0,
        timedOut: false,
        averageConfidence: nil
    )
}

struct VisibleAppContext: Codable, Hashable {
    var name: String
    var confidence: String
    var evidence: [String]
}

struct ScreenshotContext: Codable, Hashable {
    var capturedAt: Date?
    var preparedAt: Date
    var timeZoneIdentifier: String
    var source: String
    var sourceDetail: String
    var imageFilename: String
    var imageMimeType: String
    var pixelWidth: Int?
    var pixelHeight: Int?
    var originalImageBytes: Int
    var uploadImageBytes: Int
    var ocrEnabled: Bool
    var ocrDurationMs: Int?
    var ocrLineCount: Int
    var ocrCharacterCount: Int
    var ocrTimedOut: Bool
    var ocrAverageConfidence: Double?
    var visibleApp: VisibleAppContext?
}

struct CaptureUploadPayload: Codable {
    var schemaVersion: Int
    var captureId: UUID
    var createdAt: Date
    var source: String
    var sourceDetail: String
    var screenshotContext: ScreenshotContext
    var context: String
    var recognizedText: String
    var imageFilename: String
    var imageMimeType: String
    var imageBase64: String
}
