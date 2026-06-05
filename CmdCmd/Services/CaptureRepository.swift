import Foundation

enum CaptureRepository {
    private static let appGroupIdentifier = "group.com.jskoiz.cmdcmd"
    private static let settingsKey = "cmdcmd.settings.v1"
    private static let recordsKey = "cmdcmd.records.v1"
    private static let maxRecords = 40

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func loadSettings() -> RelaySettings {
        defaults.synchronize()
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
            #if DEBUG
            if let bootstrapSettings = debugBootstrapSettingsFromEnvironment() {
                saveSettings(bootstrapSettings)
                return bootstrapSettings
            }
            #endif
            return .empty
        }
    }

    static func saveSettings(_ settings: RelaySettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: settingsKey)
        defaults.synchronize()
    }

    static func loadRecords() -> [CaptureRecord] {
        defaults.synchronize()
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
        defaults.synchronize()
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
        let endpoint = environment["CMDCMD_RELAY_ENDPOINT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !endpoint.isEmpty else {
            return nil
        }

        return RelaySettings(
            endpoint: endpoint,
            apiToken: environment["CMDCMD_RELAY_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            defaultContext: environment["CMDCMD_DEFAULT_CONTEXT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            includeRecognizedText: environment["CMDCMD_INCLUDE_OCR"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "false"
        )
    }
    #endif
}
