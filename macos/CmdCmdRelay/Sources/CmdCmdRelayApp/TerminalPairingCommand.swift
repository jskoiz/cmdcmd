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

        if options.contains("--print-health-url") {
            let settings = RelaySettingsStore.load()
            print("http://127.0.0.1:\(settings.port)/healthz")
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
          CmdCmdRelayApp --print-health-url
          CmdCmdRelayApp --request-accessibility

        The installer starts the relay in the background and prints the iPhone
        pairing QR in Terminal. There is no Dock, menu bar, or dashboard UI.
        """)
    }

    private static func printPairingQRCode() {
        let settings = preparePhonePairingSettings()
        let pairingURL = settings.pairingURL.absoluteString

        print("")
        print("cmd+cmd Relay is ready and keeps running in the background.")
        print("On iPhone: open cmd+cmd, go to Settings, tap Scan Desktop QR, then scan below.")
        print("")

        if let qr = terminalQRCode(for: pairingURL) {
            print(qr)
        } else {
            print("Pairing QR could not be rendered in this terminal.")
            print("Pairing link: \(pairingURL)")
        }
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
        filter.correctionLevel = "L"

        guard let output = filter.outputImage else {
            return nil
        }

        let context = CIContext()
        guard let image = context.createCGImage(output, from: output.extent) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        let quietZone = 4
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let gridWidth = width + quietZone * 2
        let gridHeight = height + quietZone * 2
        let reset = "\u{001B}[0m"

        // A dark module reads as black; light modules and the quiet zone read
        // as white. The quiet zone is anything outside the QR bitmap.
        func isDark(_ gridX: Int, _ gridY: Int) -> Bool {
            let x = gridX - quietZone
            let y = gridY - quietZone
            guard x >= 0, x < width, y >= 0, y < height else {
                return false
            }
            let white = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceGray)?.whiteComponent ?? 1
            return white < 0.5
        }

        // Pack two vertical modules into one row with the upper half block:
        // the foreground paints the top module, the background the bottom one.
        // This halves both width and height versus one cell per module.
        var lines: [String] = []
        var gridY = 0
        while gridY < gridHeight {
            var line = ""
            for gridX in 0..<gridWidth {
                let top = isDark(gridX, gridY)
                let bottom = (gridY + 1 < gridHeight) ? isDark(gridX, gridY + 1) : false
                let foreground = top ? 30 : 97
                let background = bottom ? 40 : 107
                line += "\u{001B}[\(foreground);\(background)m\u{2580}"
            }
            line += reset
            lines.append(line)
            gridY += 2
        }

        return lines.joined(separator: "\n")
    }
}
