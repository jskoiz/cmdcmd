import AppKit
import CoreImage.CIFilterBuiltins
import Darwin
import Foundation

enum TerminalRelayCommand {
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        let options = Set(arguments.dropFirst())

        if options.contains("--help") || options.contains("-h") {
            printUsage()
            return true
        }

        if options.contains("--prepare-pairing") {
            let settings = preparePhonePairingSettings()
            print("Prepared pairing for \(settings.phoneEndpoint.absoluteString)")
            return true
        }

        if options.contains("--print-pairing-qr") {
            printPairingQRCode()
            return true
        }

        if options.contains("--accessibility-status") {
            exitAfterAccessibilityCheck(prompt: false)
        }

        if options.contains("--request-accessibility") {
            exitAfterAccessibilityCheck(prompt: true)
        }

        if options.contains("--serve") {
            serveRelay()
        }

        return false
    }

    static func printUsage() {
        print("""
        cmd+cmd Relay

        Usage:
          CmdCmdRelayApp --serve
          CmdCmdRelayApp --prepare-pairing
          CmdCmdRelayApp --print-pairing-qr
          CmdCmdRelayApp --request-accessibility

        The installer starts the relay in the background and prints the iPhone
        pairing QR in Terminal. There is no Dock, menu bar, or dashboard UI.
        """)
    }

    private static func printPairingQRCode() {
        let settings = preparePhonePairingSettings()
        let pairingURL = settings.pairingURL.absoluteString

        print("")
        print("cmd+cmd Relay is ready")
        print("1. Open cmd+cmd on iPhone.")
        print("2. Go to Settings, then tap Scan Desktop QR.")
        print("3. Scan this code to link the phone to this Mac.")
        print("")

        if let qr = terminalQRCode(for: pairingURL) {
            print(qr)
        } else {
            print("Pairing QR could not be rendered in this terminal.")
        }

        print("")
        print("Pairing link: \(pairingURL)")
        print("Endpoint: \(settings.phoneEndpoint.absoluteString)")
        print("")
        print("The relay keeps running in the background after this Terminal closes.")
        print("")
    }

    private static func serveRelay() -> Never {
        let statusStore = DeliveryStatusStore()
        let server = RelayHTTPServer(
            settingsProvider: {
                RelaySettingsStore.load()
            },
            statusStore: statusStore,
            eventHandler: { event in
                log(event)
            }
        )

        do {
            try server.start()
            let settings = RelaySettingsStore.load()
            log("ready on \(settings.phoneEndpoint.absoluteString)")
        } catch {
            fputs("cmd+cmd relay failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        interruptSource.setEventHandler {
            server.stop()
            Foundation.exit(0)
        }
        interruptSource.resume()

        let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminateSource.setEventHandler {
            server.stop()
            Foundation.exit(0)
        }
        terminateSource.resume()

        RunLoop.main.run()
        Foundation.exit(0)
    }

    private static func exitAfterAccessibilityCheck(prompt: Bool) -> Never {
        let trusted = DesktopDelivery.accessibilityTrusted(prompt: prompt)
        if trusted {
            print("Accessibility permission: granted.")
            Foundation.exit(0)
        }

        print("Accessibility permission: required.")
        print("Enable cmd+cmd Relay in System Settings > Privacy & Security > Accessibility.")
        Foundation.exit(2)
    }

    private static func preparePhonePairingSettings() -> RelaySettings {
        var settings = RelaySettingsStore.load()

        if settings.host != "0.0.0.0" {
            settings.host = "0.0.0.0"
        }

        do {
            try RelaySettingsStore.save(settings)
        } catch {
            fputs("Could not save relay settings: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }

        return settings
    }

    private static func log(_ event: RelayEvent) {
        switch event {
        case .ready(let message):
            log(message)
        case .accepted(let captureId):
            log("accepted \(short(captureId))")
        case .delivering(let captureId):
            log("attaching \(short(captureId))")
        case .delivered(let captureId):
            log("attached \(short(captureId))")
        case .failed(let message):
            log("failed: \(message)")
        }
    }

    private static func log(_ message: String) {
        fputs("[cmd+cmd] \(message)\n", stderr)
    }

    private static func short(_ captureId: String) -> String {
        String(captureId.prefix(8))
    }

    private static func terminalQRCode(for value: String) -> String? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else {
            return nil
        }

        let colored = output.applyingFilter(
            "CIFalseColor",
            parameters: [
                "inputColor0": CIColor(red: 0, green: 0, blue: 0),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1)
            ]
        )

        let context = CIContext()
        guard let image = context.createCGImage(colored, from: output.extent) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        let quietZone = 4
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let blackCell = "\u{001B}[40m  "
        let whiteCell = "\u{001B}[47m  "
        let reset = "\u{001B}[0m"
        var lines: [String] = []

        let blankLine = String(repeating: whiteCell, count: width + (quietZone * 2)) + reset
        for _ in 0..<quietZone {
            lines.append(blankLine)
        }

        for y in 0..<height {
            var line = String(repeating: whiteCell, count: quietZone)
            for x in 0..<width {
                let color = bitmap.colorAt(x: x, y: y)
                let white = color?.usingColorSpace(.deviceGray)?.whiteComponent ?? 1
                line += white < 0.5 ? blackCell : whiteCell
            }
            line += String(repeating: whiteCell, count: quietZone)
            line += reset
            lines.append(line)
        }

        for _ in 0..<quietZone {
            lines.append(blankLine)
        }

        return lines.joined(separator: "\n")
    }
}
