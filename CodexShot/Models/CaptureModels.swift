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
