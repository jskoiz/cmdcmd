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
    var threadHint: String
    var includeRecognizedText: Bool

    static let empty = RelaySettings(
        endpoint: "",
        apiToken: "",
        defaultContext: "",
        threadHint: "",
        includeRecognizedText: true
    )
}

struct CaptureUploadPayload: Codable {
    var schemaVersion: Int
    var captureId: UUID
    var createdAt: Date
    var source: String
    var sourceDetail: String
    var context: String
    var recognizedText: String
    var threadHint: String
    var imageFilename: String
    var imageMimeType: String
    var imageBase64: String
}

