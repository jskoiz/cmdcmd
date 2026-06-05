import Foundation

struct StoredCapture {
    var imagePath: String
    var metadataPath: String
}

enum CaptureStorage {
    static func persist(_ capture: CapturePayload, inboxDirectory: String) throws -> StoredCapture {
        let date = String(capture.createdAt.prefix(10))
        let targetDirectory = URL(fileURLWithPath: inboxDirectory, isDirectory: true)
            .appendingPathComponent(date, isDirectory: true)
        try FileManager.default.createDirectory(
            at: targetDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let stem = "\(capture.createdAt.replacingOccurrences(of: ":", with: "-"))-\(capture.captureId)"
        let imageName = "\(stem)-\(safeBaseName(capture.imageFilename, mimeType: capture.imageMimeType))"
        let imageURL = try nextAvailableURL(targetDirectory.appendingPathComponent(imageName))
        let metadataURL = try nextAvailableURL(targetDirectory.appendingPathComponent("\(stem).json"))

        try capture.imageData.write(to: imageURL, options: [.withoutOverwriting])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL.path)

        let metadata = StoredCaptureMetadata(capture: capture, imagePath: imageURL.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataURL, options: [.withoutOverwriting])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)

        return StoredCapture(imagePath: imageURL.path, metadataPath: metadataURL.path)
    }

    private static func safeBaseName(_ filename: String, mimeType: String) -> String {
        let url = URL(fileURLWithPath: filename)
        let rawStem = url.deletingPathExtension().lastPathComponent.isEmpty
            ? "screenshot"
            : url.deletingPathExtension().lastPathComponent
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let stem = String(rawStem.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .prefix(80)
        let ext = mimeType == "image/jpeg" ? ".jpg" : ".png"
        return "\(stem.isEmpty ? "screenshot" : String(stem))\(ext)"
    }

    private static func nextAvailableURL(_ targetURL: URL) throws -> URL {
        if !FileManager.default.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        let directory = targetURL.deletingLastPathComponent()
        let stem = targetURL.deletingPathExtension().lastPathComponent
        let ext = targetURL.pathExtension
        for index in 1..<1000 {
            let candidate = directory.appendingPathComponent("\(stem)-\(index)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw RelayHTTPError.server("Unable to find an unused path for \(targetURL.path).")
    }
}

private struct StoredCaptureMetadata: Encodable {
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
    var imagePath: String

    init(capture: CapturePayload, imagePath: String) {
        self.schemaVersion = capture.schemaVersion
        self.captureId = capture.captureId
        self.createdAt = capture.createdAt
        self.source = capture.source
        self.sourceDetail = capture.sourceDetail
        self.screenshotContext = capture.screenshotContext
        self.context = capture.context
        self.recognizedText = capture.recognizedText
        self.imageFilename = capture.imageFilename
        self.imageMimeType = capture.imageMimeType
        self.imagePath = imagePath
    }
}

