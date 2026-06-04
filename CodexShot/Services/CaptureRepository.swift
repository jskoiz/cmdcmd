import Foundation

enum CaptureRepository {
    private static let appGroupIdentifier = "group.com.jskoiz.codexshot"
    private static let settingsKey = "codexshot.settings.v1"
    private static let recordsKey = "codexshot.records.v1"
    private static let maxRecords = 40

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func loadSettings() -> RelaySettings {
        guard let data = defaults.data(forKey: settingsKey) else {
            #if DEBUG
            if let bootstrapSettings = debugBootstrapSettingsFromEnvironment() {
                saveSettings(bootstrapSettings)
                return bootstrapSettings
            }
            #endif
            return .empty
        }

        do {
            let settings = try JSONDecoder().decode(RelaySettings.self, from: data)
            #if DEBUG
            if settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let bootstrapSettings = debugBootstrapSettingsFromEnvironment() {
                saveSettings(bootstrapSettings)
                return bootstrapSettings
            }
            #endif
            return settings
        } catch {
            return .empty
        }
    }

    static func saveSettings(_ settings: RelaySettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: settingsKey)
    }

    static func loadRecords() -> [CaptureRecord] {
        guard let data = defaults.data(forKey: recordsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([CaptureRecord].self, from: data)
        } catch {
            return []
        }
    }

    static func saveRecords(_ records: [CaptureRecord]) {
        let cappedRecords = Array(records.sorted { $0.createdAt > $1.createdAt }.prefix(maxRecords))
        guard let data = try? JSONEncoder().encode(cappedRecords) else {
            return
        }
        defaults.set(data, forKey: recordsKey)
    }

    static func upsert(_ record: CaptureRecord) {
        var records = loadRecords()
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.insert(record, at: 0)
        }
        saveRecords(records)
    }

    static func clearRecords() {
        defaults.removeObject(forKey: recordsKey)
    }

    #if DEBUG
    private static func debugBootstrapSettingsFromEnvironment() -> RelaySettings? {
        let environment = ProcessInfo.processInfo.environment
        let endpoint = environment["CODEXSHOT_RELAY_ENDPOINT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !endpoint.isEmpty else {
            return nil
        }

        return RelaySettings(
            endpoint: endpoint,
            apiToken: environment["CODEXSHOT_RELAY_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            defaultContext: environment["CODEXSHOT_DEFAULT_CONTEXT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            threadHint: environment["CODEXSHOT_THREAD_HINT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            includeRecognizedText: environment["CODEXSHOT_INCLUDE_OCR"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "false"
        )
    }
    #endif
}
