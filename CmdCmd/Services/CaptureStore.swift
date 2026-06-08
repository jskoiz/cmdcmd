import Foundation
import Observation
import OSLog

private let captureStoreLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.jskoiz.CmdCmd",
    category: "CaptureStore"
)

@MainActor
@Observable
final class CaptureStore {
    var settings: RelaySettings
    var records: [CaptureRecord]

    init() {
        self.settings = CaptureRepository.loadSettings()
        self.records = CaptureRepository.loadRecords()
    }

    var hasEndpoint: Bool {
        !settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveSettings(_ updatedSettings: RelaySettings) {
        settings = updatedSettings
        CaptureRepository.saveSettings(updatedSettings)
    }

    func applyPairing(endpoint: String, apiToken: String) {
        var updatedSettings = settings
        updatedSettings.endpoint = endpoint
        updatedSettings.apiToken = apiToken
        saveSettings(updatedSettings)
        captureStoreLogger.info(
            "pairing stored endpointHost=\(URL(string: endpoint)?.host() ?? "invalid", privacy: .public) tokenSuffix=\(tokenSuffix(apiToken), privacy: .public)"
        )
    }

    func reload() {
        settings = CaptureRepository.loadSettings()
        records = CaptureRepository.loadRecords()
    }

    func clearHistory() {
        CaptureRepository.clearRecords()
        records = []
    }

    func submit(
        imageData: Data,
        filename: String,
        note: String,
        source: CaptureSource,
        imageMetadata: CaptureImageMetadata = .empty
    ) async -> CaptureRecord {
        let record = await CapturePipeline.submit(
            imageData: imageData,
            filename: filename,
            note: note,
            source: source,
            imageMetadata: imageMetadata
        )
        reload()
        return record
    }
}
