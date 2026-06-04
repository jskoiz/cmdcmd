import AppIntents
import Foundation
import UniformTypeIdentifiers

struct SendScreenshotToCodexIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Screenshot to Codex"
    static var description = IntentDescription("Uploads an image with optional context to the configured Codex relay.")
    static var openAppWhenRun = false

    @Parameter(
        title: "Screenshot",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    @Parameter(title: "Context", default: "")
    var context: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = try await screenshot.data(contentType: .image)
        let record = await CapturePipeline.submit(
            imageData: data,
            filename: screenshot.filename.isEmpty ? "screenshot.png" : screenshot.filename,
            note: context,
            source: .shortcut,
            sourceDetail: "App Intent"
        )

        return .result(dialog: IntentDialog(stringLiteral: record.statusMessage))
    }
}

struct SendLatestScreenshotToCodexIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Latest Screenshot to Codex"
    static var description = IntentDescription("Uploads the most recent screenshot in Photos to the configured Codex relay.")
    static var openAppWhenRun = false

    @Parameter(title: "Context", default: "")
    var context: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let screenshot = try await LatestScreenshotProvider.loadLatestScreenshot()
            let record = await CapturePipeline.submit(
                imageData: screenshot.data,
                filename: screenshot.filename,
                note: context,
                source: .shortcut,
                sourceDetail: "Latest Screenshot"
            )

            return .result(dialog: IntentDialog(stringLiteral: record.statusMessage))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        }
    }
}

struct CodexShotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendLatestScreenshotToCodexIntent(),
            phrases: [
                "Send latest screenshot to \(.applicationName)",
                "Send my latest screenshot to \(.applicationName)"
            ],
            shortTitle: "Latest Screenshot",
            systemImageName: "photo"
        )

        AppShortcut(
            intent: SendScreenshotToCodexIntent(),
            phrases: [
                "Send screenshot to \(.applicationName)",
                "Send this to \(.applicationName)"
            ],
            shortTitle: "Send Screenshot",
            systemImageName: "camera.viewfinder"
        )
    }
}
