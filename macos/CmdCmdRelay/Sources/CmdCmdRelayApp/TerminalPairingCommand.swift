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
            let settings = preparePhonePairingSettings(deliveryMode: .codex)
            print("Prepared pairing for \(settings.phoneEndpoint.absoluteString)")
            return true
        }

        if options.contains("--prepare-review-pairing") {
            let settings = preparePhonePairingSettings(deliveryMode: .reviewInbox)
            print("Prepared review pairing for \(settings.phoneEndpoint.absoluteString)")
            return true
        }

        if options.contains("--print-pairing-qr") {
            printPairingQRCode()
            return true
        }

        if options.contains("--print-health-url") {
            let settings = loadSettingsOrExit()
            print("http://127.0.0.1:\(settings.port)/healthz")
            return true
        }

        if options.contains("--accessibility-status") {
            exitAfterAccessibilityCheck(prompt: false)
        }

        if options.contains("--request-accessibility") {
            exitAfterAccessibilityCheck(prompt: true)
        }

        if options.contains("--serve-detached") {
            serveDetached()
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
          CmdCmdRelayApp --serve-detached
          CmdCmdRelayApp --prepare-pairing
          CmdCmdRelayApp --prepare-review-pairing
          CmdCmdRelayApp --print-pairing-qr
          CmdCmdRelayApp --print-health-url
          CmdCmdRelayApp --accessibility-status
          CmdCmdRelayApp --request-accessibility

        The installer starts the relay in the background and prints the iPhone
        pairing QR in Terminal. There is no Dock, menu bar, or dashboard UI.
        """)
    }

    private static func serveDetached() -> Never {
        guard let executablePath = Bundle.main.executablePath ?? CommandLine.arguments.first else {
            fputs("cmd+cmd relay failed: could not resolve executable path.\n", stderr)
            Foundation.exit(1)
        }

        var attributes: posix_spawnattr_t?
        var result = posix_spawnattr_init(&attributes)
        guard result == 0 else {
            fputs("cmd+cmd relay failed to initialize detached launch: \(String(cString: strerror(result)))\n", stderr)
            Foundation.exit(1)
        }
        defer {
            posix_spawnattr_destroy(&attributes)
        }

        result = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        guard result == 0 else {
            fputs("cmd+cmd relay failed to configure detached launch: \(String(cString: strerror(result)))\n", stderr)
            Foundation.exit(1)
        }

        var arguments = [
            strdup(executablePath),
            strdup("--serve"),
            nil
        ]
        defer {
            for case let argument? in arguments {
                free(argument)
            }
        }

        var pid = pid_t()
        result = executablePath.withCString { path in
            arguments.withUnsafeMutableBufferPointer { buffer in
                posix_spawn(&pid, path, nil, &attributes, buffer.baseAddress, environ)
            }
        }
        guard result == 0 else {
            fputs("cmd+cmd relay failed to launch detached service: \(String(cString: strerror(result)))\n", stderr)
            Foundation.exit(1)
        }

        Foundation.exit(0)
    }

    private static func printPairingQRCode() {
        let settings = preparePhonePairingSettings()
        let pairingURL = settings.compactPairingURL.absoluteString

        print("")
        print("cmd+cmd Relay is ready and keeps running in the background.")
        if settings.deliveryMode == .reviewInbox {
            print("Review inbox mode is enabled. Codex Desktop is not required.")
        }
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
                try RelaySettingsStore.loadOrCreate()
            },
            statusStore: statusStore,
            eventHandler: { event in
                log(event)
            }
        )

        do {
            try server.start()
            let settings = try RelaySettingsStore.loadOrCreate()
            log("ready on \(settings.phoneEndpoint.absoluteString) (\(settings.deliveryMode.logLabel))")
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

    private static func preparePhonePairingSettings(deliveryMode: RelayDeliveryMode? = nil) -> RelaySettings {
        do {
            var settings = try RelaySettingsStore.loadOrCreate()
            settings.host = "0.0.0.0"
            if let deliveryMode {
                settings.deliveryMode = deliveryMode
            }
            try RelaySettingsStore.save(settings)
            return settings
        } catch {
            fputs("Could not prepare relay settings: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func loadSettingsOrExit() -> RelaySettings {
        do {
            return try RelaySettingsStore.loadOrCreate()
        } catch {
            fputs("Could not load relay settings: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
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
        let quietZone = 2
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let reset = "\u{001B}[0m"
        var lines: [String] = []
        let totalWidth = width + (quietZone * 2)
        let totalHeight = height + (quietZone * 2)

        for y in stride(from: 0, to: totalHeight, by: 2) {
            var line = ""
            for x in 0..<totalWidth {
                let topIsDark = qrPixelIsDark(bitmap: bitmap, x: x - quietZone, y: y - quietZone)
                let bottomIsDark = qrPixelIsDark(bitmap: bitmap, x: x - quietZone, y: y + 1 - quietZone)
                line += terminalHalfBlock(topIsDark: topIsDark, bottomIsDark: bottomIsDark)
            }
            line += reset
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    private static func qrPixelIsDark(bitmap: NSBitmapImageRep, x: Int, y: Int) -> Bool {
        guard x >= 0, x < bitmap.pixelsWide, y >= 0, y < bitmap.pixelsHigh else {
            return false
        }

        let color = bitmap.colorAt(x: x, y: y)
        let white = color?.usingColorSpace(.deviceGray)?.whiteComponent ?? 1
        return white < 0.5
    }

    private static func terminalHalfBlock(topIsDark: Bool, bottomIsDark: Bool) -> String {
        let foreground = topIsDark ? "\u{001B}[30m" : "\u{001B}[97m"
        let background = bottomIsDark ? "\u{001B}[40m" : "\u{001B}[107m"
        return foreground + background + "▀"
    }
}

private extension RelayDeliveryMode {
    var logLabel: String {
        switch self {
        case .codex:
            return "Codex Desktop mode"
        case .reviewInbox:
            return "review inbox mode"
        }
    }
}
