import Foundation

enum RelayHTTPError: Error, LocalizedError {
    case badRequest(String)
    case unauthorized
    case notFound(String)
    case payloadTooLarge
    case unsupportedMediaType(String)
    case server(String)

    var statusCode: Int {
        switch self {
        case .badRequest:
            return 400
        case .unauthorized:
            return 401
        case .notFound:
            return 404
        case .payloadTooLarge:
            return 413
        case .unsupportedMediaType:
            return 415
        case .server:
            return 502
        }
    }

    var errorDescription: String? {
        switch self {
        case .badRequest(let message),
             .notFound(let message),
             .unsupportedMediaType(let message),
             .server(let message):
            return message
        case .unauthorized:
            return "Unauthorized."
        case .payloadTooLarge:
            return "Request body is too large."
        }
    }
}

struct CapturePayload {
    var schemaVersion: Int
    var captureId: String
    var createdAt: String
    var source: String
    var sourceDetail: String
    var screenshotContext: ScreenshotContext
    var context: String
    var recognizedText: String
    var imageFilename: String
    var imageMimeType: String
    var imageData: Data

    static func decode(from data: Data) throws -> CapturePayload {
        try PayloadValidator.rejectUnsupportedFields(in: data)
        let decoded = try JSONDecoder().decode(RawCapturePayload.self, from: data)

        guard decoded.schemaVersion == 2 else {
            throw RelayHTTPError.badRequest("schemaVersion must be 2.")
        }
        guard UUID(uuidString: decoded.captureId) != nil else {
            throw RelayHTTPError.badRequest("captureId must be a UUID string.")
        }
        guard !decoded.createdAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ISO8601DateFormatter().date(from: decoded.createdAt) != nil else {
            throw RelayHTTPError.badRequest("createdAt must be an ISO date string.")
        }
        guard ["image/png", "image/jpeg"].contains(decoded.imageMimeType) else {
            throw RelayHTTPError.badRequest("imageMimeType must be image/png or image/jpeg.")
        }

        let compactBase64 = decoded.imageBase64.filter { !$0.isWhitespace }
        guard let imageData = Data(base64Encoded: String(compactBase64)), !imageData.isEmpty else {
            throw RelayHTTPError.badRequest("imageBase64 is not valid base64.")
        }

        return CapturePayload(
            schemaVersion: 2,
            captureId: decoded.captureId.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: decoded.createdAt.trimmingCharacters(in: .whitespacesAndNewlines),
            source: try PayloadValidator.required(decoded.source, "source"),
            sourceDetail: decoded.sourceDetail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            screenshotContext: try decoded.screenshotContext.validated(),
            context: decoded.context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            recognizedText: decoded.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            imageFilename: try PayloadValidator.required(decoded.imageFilename, "imageFilename"),
            imageMimeType: decoded.imageMimeType,
            imageData: imageData
        )
    }
}

private struct RawCapturePayload: Decodable {
    var schemaVersion: Int
    var captureId: String
    var createdAt: String
    var source: String
    var sourceDetail: String?
    var screenshotContext: ScreenshotContext
    var context: String?
    var recognizedText: String?
    var imageFilename: String
    var imageMimeType: String
    var imageBase64: String
}

struct ScreenshotContext: Codable {
    var capturedAt: String?
    var preparedAt: String
    var timeZoneIdentifier: String?
    var source: String
    var sourceDetail: String?
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
    var visibleApp: VisibleApp?

    func validated() throws -> ScreenshotContext {
        guard ISO8601DateFormatter().date(from: preparedAt) != nil else {
            throw RelayHTTPError.badRequest("screenshotContext.preparedAt must be an ISO date string.")
        }
        if let capturedAt, ISO8601DateFormatter().date(from: capturedAt) == nil {
            throw RelayHTTPError.badRequest("screenshotContext.capturedAt must be an ISO date string.")
        }
        try PayloadValidator.requirePositive(pixelWidth, "screenshotContext.pixelWidth")
        try PayloadValidator.requirePositive(pixelHeight, "screenshotContext.pixelHeight")
        try PayloadValidator.requireNonNegative(originalImageBytes, "screenshotContext.originalImageBytes")
        try PayloadValidator.requireNonNegative(uploadImageBytes, "screenshotContext.uploadImageBytes")
        try PayloadValidator.requireNonNegative(ocrDurationMs, "screenshotContext.ocrDurationMs")
        try PayloadValidator.requireNonNegative(ocrLineCount, "screenshotContext.ocrLineCount")
        try PayloadValidator.requireNonNegative(ocrCharacterCount, "screenshotContext.ocrCharacterCount")
        if let confidence = ocrAverageConfidence, confidence < 0 || confidence > 1 {
            throw RelayHTTPError.badRequest("screenshotContext.ocrAverageConfidence must be between 0 and 1.")
        }
        _ = try PayloadValidator.required(source, "screenshotContext.source")
        _ = try PayloadValidator.required(imageFilename, "screenshotContext.imageFilename")
        _ = try PayloadValidator.required(imageMimeType, "screenshotContext.imageMimeType")
        return self
    }
}

struct VisibleApp: Codable {
    var name: String
    var confidence: String
    var evidence: [String]
}

private enum PayloadValidator {
    private static let payloadFields: Set<String> = [
        "schemaVersion",
        "captureId",
        "createdAt",
        "source",
        "sourceDetail",
        "screenshotContext",
        "context",
        "recognizedText",
        "imageFilename",
        "imageMimeType",
        "imageBase64"
    ]
    private static let screenshotContextFields: Set<String> = [
        "capturedAt",
        "preparedAt",
        "timeZoneIdentifier",
        "source",
        "sourceDetail",
        "imageFilename",
        "imageMimeType",
        "pixelWidth",
        "pixelHeight",
        "originalImageBytes",
        "uploadImageBytes",
        "ocrEnabled",
        "ocrDurationMs",
        "ocrLineCount",
        "ocrCharacterCount",
        "ocrTimedOut",
        "ocrAverageConfidence",
        "visibleApp"
    ]
    private static let visibleAppFields: Set<String> = ["name", "confidence", "evidence"]

    static func rejectUnsupportedFields(in data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RelayHTTPError.badRequest("Request body must be a JSON object.")
        }
        try rejectUnsupportedFields(in: object, allowed: payloadFields, label: "payload")

        guard let context = object["screenshotContext"] as? [String: Any] else {
            throw RelayHTTPError.badRequest("screenshotContext is required.")
        }
        try rejectUnsupportedFields(in: context, allowed: screenshotContextFields, label: "screenshotContext")

        if let visibleApp = context["visibleApp"], !(visibleApp is NSNull) {
            guard let visibleAppObject = visibleApp as? [String: Any] else {
                throw RelayHTTPError.badRequest("screenshotContext.visibleApp must be an object.")
            }
            try rejectUnsupportedFields(
                in: visibleAppObject,
                allowed: visibleAppFields,
                label: "screenshotContext.visibleApp"
            )
        }
    }

    static func required(_ value: String, _ field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RelayHTTPError.badRequest("\(field) is required.")
        }
        return trimmed
    }

    static func requirePositive(_ value: Int?, _ field: String) throws {
        guard let value else {
            return
        }
        guard value > 0 else {
            throw RelayHTTPError.badRequest("\(field) must be a positive integer.")
        }
    }

    static func requireNonNegative(_ value: Int?, _ field: String) throws {
        guard let value else {
            return
        }
        guard value >= 0 else {
            throw RelayHTTPError.badRequest("\(field) must be a non-negative integer.")
        }
    }

    static func requireNonNegative(_ value: Int, _ field: String) throws {
        guard value >= 0 else {
            throw RelayHTTPError.badRequest("\(field) must be a non-negative integer.")
        }
    }

    private static func rejectUnsupportedFields(
        in dictionary: [String: Any],
        allowed: Set<String>,
        label: String
    ) throws {
        if let unsupported = dictionary.keys.first(where: { !allowed.contains($0) }) {
            throw RelayHTTPError.badRequest("Unsupported \(label) field: \(unsupported).")
        }
    }
}

