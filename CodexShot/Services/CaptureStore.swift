import Foundation
import Observation

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
