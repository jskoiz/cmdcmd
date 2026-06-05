import AppKit
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI

@MainActor
final class RelayController: ObservableObject {
    @Published private(set) var settings: RelaySettings
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Starting relay"
    @Published private(set) var lastEvent = "No captures yet"
    @Published private(set) var accessibilityTrusted = false
    @Published var tokenVisible = false

    private var server: RelayHTTPServer?
    private let statusStore = DeliveryStatusStore()
    private let settingsVault: SettingsVault

    init() {
        let loadedSettings = RelaySettingsStore.load()
        settings = loadedSettings
        settingsVault = SettingsVault(loadedSettings)
        refreshAccessibilityTrust(prompt: false)
        start()
    }

    var endpointForDisplay: String {
        settings.phoneEndpoint.absoluteString
    }

    var tokenForDisplay: String {
        tokenVisible ? settings.token : "••••••••••••••••••••••••"
    }

    var pairingURLString: String {
        settings.pairingURL.absoluteString
    }

    var qrImage: NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(pairingURLString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else {
            return nil
        }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: 192, height: 192))
    }

    func start() {
        stop()
        do {
            let server = RelayHTTPServer(
                settingsProvider: { [settingsVault] in settingsVault.current() },
                statusStore: statusStore,
                eventHandler: { [weak self] event in
                    DispatchQueue.main.async {
                        self?.handle(event)
                    }
                }
            )
            try server.start()
            self.server = server
            isRunning = true
            statusText = "Relay ready"
            lastEvent = settings.listensOnPrivateNetwork
                ? "Listening on private network"
                : "Listening on localhost"
        } catch {
            isRunning = false
            statusText = "Relay failed"
            lastEvent = error.localizedDescription
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
    }

    func restart() {
        start()
    }

    func setPrivateNetworkEnabled(_ enabled: Bool) {
        mutateSettings { settings in
            settings.host = enabled ? "0.0.0.0" : "127.0.0.1"
        }
        restart()
    }

    func rotateToken() {
        mutateSettings { settings in
            settings.token = TokenGenerator.randomToken()
        }
        restart()
    }

    func copyEndpoint() {
        copyToPasteboard(endpointForDisplay)
    }

    func copyToken() {
        copyToPasteboard(settings.token)
    }

    func copyPairingLink() {
        copyToPasteboard(pairingURLString)
    }

    func revealInbox() {
        let url = URL(fileURLWithPath: settings.inboxDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openAccessibilitySettings() {
        refreshAccessibilityTrust(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshAccessibilityTrust(prompt: Bool) {
        accessibilityTrusted = DesktopDelivery.accessibilityTrusted(prompt: prompt)
    }

    private func mutateSettings(_ body: (inout RelaySettings) -> Void) {
        var updated = settings
        body(&updated)
        settings = updated
        settingsVault.update(updated)
        do {
            try RelaySettingsStore.save(updated)
        } catch {
            lastEvent = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        lastEvent = "Copied to pasteboard"
    }

    private func handle(_ event: RelayEvent) {
        switch event {
        case .ready(let message):
            statusText = "Relay ready"
            lastEvent = message
        case .accepted(let captureId):
            lastEvent = "Accepted \(short(captureId))"
        case .delivering(let captureId):
            lastEvent = "Attaching \(short(captureId))"
        case .delivered(let captureId):
            lastEvent = "Attached \(short(captureId))"
        case .failed(let message):
            lastEvent = message
        }
    }

    private func short(_ captureId: String) -> String {
        String(captureId.prefix(8))
    }
}

private final class SettingsVault {
    private var settings: RelaySettings
    private let lock = NSLock()

    init(_ settings: RelaySettings) {
        self.settings = settings
    }

    func current() -> RelaySettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    func update(_ settings: RelaySettings) {
        lock.lock()
        self.settings = settings
        lock.unlock()
    }
}
