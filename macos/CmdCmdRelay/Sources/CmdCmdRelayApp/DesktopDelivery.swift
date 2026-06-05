import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum DesktopDelivery {
    static func deliver(capture: CapturePayload, stored: StoredCapture, settings: RelaySettings) throws {
        try requireAccessibilityTrust()

        let contextPath = try writeContextAttachment(capture: capture, stored: stored)

        guard let codex = launchOrActivate(bundleIdentifier: settings.codexBundleIdentifier) else {
            throw RelayHTTPError.server("Could not activate Codex app bundle \(settings.codexBundleIdentifier).")
        }

        Thread.sleep(forTimeInterval: Double(settings.pasteDelayMilliseconds) / 1000.0)
        try pasteAttachmentsIntoCodex(app: codex, imagePath: stored.imagePath, contextPath: contextPath)
    }

    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: prompt] as CFDictionary)
    }

    private static func requireAccessibilityTrust() throws {
        guard accessibilityTrusted(prompt: false) else {
            throw RelayHTTPError.server(
                "Accessibility is still not available to the background relay. In System Settings, turn cmd+cmd Relay off and back on, then rerun the Mac installer."
            )
        }
    }

    private static func runningApplication(bundleIdentifier: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }

    private static func launchOrActivate(bundleIdentifier: String) -> NSRunningApplication? {
        if let app = runningApplication(bundleIdentifier: bundleIdentifier) {
            activate(app)
            return app
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let semaphore = DispatchSemaphore(value: 0)
        final class Box {
            var app: NSRunningApplication?
        }
        let box = Box()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
            box.app = app
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return box.app ?? runningApplication(bundleIdentifier: bundleIdentifier)
    }

    private static func writeContextAttachment(capture: CapturePayload, stored: StoredCapture) throws -> String? {
        guard let text = attachmentText(capture: capture) else {
            return nil
        }

        let metadataURL = URL(fileURLWithPath: stored.metadataPath)
        let textURL = metadataURL.deletingPathExtension().appendingPathExtension("txt")
        try "\(text)\n".write(to: textURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: textURL.path)
        return textURL.path
    }

    private static func copyImageToPasteboard(_ imagePath: String) throws {
        guard let image = NSImage(contentsOfFile: imagePath) else {
            throw RelayHTTPError.server("Could not load image: \(imagePath).")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.writeObjects([image]) {
            return
        }

        guard let tiff = image.tiffRepresentation else {
            throw RelayHTTPError.server("Could not encode image for pasteboard.")
        }
        pasteboard.setData(tiff, forType: .tiff)
    }

    private static func copyFileToPasteboard(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RelayHTTPError.server("Could not find context attachment: \(path).")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.writeObjects([url as NSURL]) {
            return
        }

        pasteboard.setString(url.absoluteString, forType: .fileURL)
    }

    private static func pasteAttachmentsIntoCodex(
        app: NSRunningApplication,
        imagePath: String,
        contextPath: String?
    ) throws {
        let source = try eventSource()
        let frame = try focusedWindowFrame(for: app)
        let clickPoint = CGPoint(
            x: frame.origin.x + frame.width / 2,
            y: frame.origin.y + frame.height - 70
        )

        postKey(source, key: 53, down: true)
        postKey(source, key: 53, down: false)
        usleep(100_000)
        try postClick(source, point: clickPoint)
        usleep(150_000)

        try copyImageToPasteboard(imagePath)
        try postPaste(source)

        if let contextPath {
            usleep(300_000)
            try copyFileToPasteboard(contextPath)
            try postPaste(source)
        }
    }

    private static func focusedWindowFrame(for app: NSRunningApplication) throws -> CGRect {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(
            element,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        guard windowsResult == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first else {
            throw RelayHTTPError.server("Could not read Codex window bounds.")
        }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
        let sizeResult = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard positionResult == .success,
              sizeResult == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef else {
            throw RelayHTTPError.server("Could not read Codex window frame.")
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            throw RelayHTTPError.server("Could not decode Codex window frame.")
        }

        return CGRect(origin: position, size: size)
    }

    private static func eventSource() throws -> CGEventSource {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw RelayHTTPError.server("Could not create event source.")
        }
        source.localEventsSuppressionInterval = 0
        return source
    }

    private static func postKey(
        _ source: CGEventSource,
        key: CGKeyCode,
        down: Bool,
        flags: CGEventFlags = []
    ) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        usleep(30_000)
    }

    private static func postPaste(_ source: CGEventSource) throws {
        postKey(source, key: 55, down: true, flags: .maskCommand)
        postKey(source, key: 9, down: true, flags: .maskCommand)
        postKey(source, key: 9, down: false, flags: .maskCommand)
        postKey(source, key: 55, down: false)
    }

    private static func postClick(_ source: CGEventSource, point: CGPoint) throws {
        guard let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw RelayHTTPError.server("Could not create mouse event.")
        }

        move.post(tap: .cghidEventTap)
        usleep(30_000)
        down.post(tap: .cghidEventTap)
        usleep(30_000)
        up.post(tap: .cghidEventTap)
        usleep(30_000)
    }

    private static func attachmentText(capture: CapturePayload) -> String? {
        let rawRecognizedText = capture.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let recognizedText = OCRAttachmentTextCleaner.clean(rawRecognizedText)
        let sections = [
            screenshotContextText(
                capture.screenshotContext,
                rawRecognizedText: rawRecognizedText,
                recognizedText: recognizedText
            ),
            capture.context.isEmpty ? nil : "Context:\n\(capture.context)",
            recognizedText.isEmpty ? nil : "OCR text:\n\(recognizedText)"
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        let body = sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    private static func cleanInline(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    private static func screenshotContextText(
        _ context: ScreenshotContext,
        rawRecognizedText: String,
        recognizedText: String
    ) -> String? {
        var lines: [String] = []
        let source = [humanizedSource(context.source), context.sourceDetail]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        if !source.isEmpty {
            lines.append("Source: \(source)")
        }
        lines.append("Prepared: \(context.preparedAt)")
        if let capturedAt = context.capturedAt {
            lines.append("Captured: \(capturedAt)")
        }
        if let visibleApp = context.visibleApp {
            let evidence = visibleApp.evidence.isEmpty ? "" : " from \(visibleApp.evidence.joined(separator: ", "))"
            lines.append("Visible app: \(visibleApp.name) (\(visibleApp.confidence) inference\(evidence))")
        }
        if let width = context.pixelWidth, let height = context.pixelHeight {
            lines.append("Image: \(context.imageFilename); \(context.imageMimeType); \(width)x\(height)")
        } else {
            lines.append("Image: \(context.imageFilename); \(context.imageMimeType)")
        }
        lines.append(ocrSummary(context, rawRecognizedText: rawRecognizedText, recognizedText: recognizedText))

        return "Screenshot context:\n\(lines.joined(separator: "\n"))"
    }

    private static func ocrSummary(
        _ context: ScreenshotContext,
        rawRecognizedText: String,
        recognizedText: String
    ) -> String {
        guard context.ocrEnabled else {
            return "OCR: off"
        }

        if context.ocrTimedOut {
            return "OCR: timed out"
        }

        let cleanedStats = OCRAttachmentTextCleaner.stats(for: recognizedText)
        if cleanedStats.lineCount > 0 {
            let filtered = cleanedStats.lineCount < context.ocrLineCount
                || cleanedStats.characterCount < context.ocrCharacterCount
            let lineLabel = "\(cleanedStats.lineCount) \(filtered ? "useful " : "")line\(cleanedStats.lineCount == 1 ? "" : "s")"
            return "OCR: \(lineLabel), \(cleanedStats.characterCount) character\(cleanedStats.characterCount == 1 ? "" : "s")"
        }

        let rawStats = OCRAttachmentTextCleaner.stats(for: rawRecognizedText)
        if context.ocrLineCount > 0 || context.ocrCharacterCount > 0 || rawStats.lineCount > 0 {
            return "OCR: noisy text omitted"
        }

        return "OCR: no useful text"
    }

    private static func humanizedSource(_ value: String) -> String? {
        switch value {
        case "mainApp":
            return "Main app"
        case "shareExtension":
            return "Share extension"
        case "shortcut":
            return "Shortcut"
        default:
            return value
        }
    }

    private static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}

private enum OCRAttachmentTextCleaner {
    struct TextStats {
        var lineCount: Int
        var characterCount: Int
    }

    private static let maxLines = 16
    private static let maxCharacters = 1_200
    private static let ignoredStatusLines: Set<String> = [
        "phone"
    ]
    private static let allowedTrailingCharacters = Set(".!?%")

    static func clean(_ value: String) -> String {
        let lines = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)

        var cleanedLines: [String] = []
        var seenKeys = Set<String>()
        var characterCount = 0

        for rawLine in lines {
            guard let line = cleanedText(String(rawLine)),
                  isInformative(line) else {
                continue
            }

            let key = dedupeKey(line)
            guard !key.isEmpty, !seenKeys.contains(key) else {
                continue
            }

            let nextCharacterCount = characterCount + line.count + (cleanedLines.isEmpty ? 0 : 1)
            guard cleanedLines.isEmpty || nextCharacterCount <= maxCharacters else {
                break
            }

            cleanedLines.append(line)
            seenKeys.insert(key)
            characterCount = nextCharacterCount

            if cleanedLines.count >= maxLines {
                break
            }
        }

        return cleanedLines.joined(separator: "\n")
    }

    static func stats(for value: String) -> TextStats {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return TextStats(lineCount: 0, characterCount: 0)
        }

        let lineCount = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        return TextStats(lineCount: lineCount, characterCount: text.count)
    }

    private static func cleanedText(_ rawText: String) -> String? {
        var text = normalizedWhitespace(rawText)
        text = strippedEdgeJunk(text)

        var tokens = text.split(separator: " ").map(String.init)
        while tokens.count > 1, isLeadingArtifact(tokens[0]) {
            tokens.removeFirst()
        }

        text = strippedEdgeJunk(tokens.joined(separator: " "))
        return text.isEmpty ? nil : text
    }

    private static func isInformative(_ text: String) -> Bool {
        let key = dedupeKey(text)
        guard !key.isEmpty, !ignoredStatusLines.contains(key) else {
            return false
        }

        if text.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil {
            return false
        }

        let letters = text.unicodeScalars.filter(isLetter).count
        guard letters > 0 else {
            return false
        }

        let usefulWords = key.split(separator: " ").filter { word in
            word.count >= 3 && word.unicodeScalars.contains(where: isLetter)
        }
        guard !usefulWords.isEmpty else {
            return false
        }

        let digits = text.unicodeScalars.filter(isDigit).count
        let noisySymbols = text.unicodeScalars.filter { scalar in
            !isLetter(scalar)
                && !isDigit(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet(charactersIn: ".,:;!?%+#@&()/-").contains(scalar)
        }.count
        return noisySymbols <= letters + digits
    }

    private static func isLeadingArtifact(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        guard !scalars.isEmpty else {
            return true
        }

        if scalars.allSatisfy(isDigit) {
            return true
        }

        if scalars.allSatisfy({ !isLetter($0) && !isDigit($0) }) {
            return true
        }

        let normalized = token.lowercased()
        return normalized.count == 1 && normalized != "a" && normalized != "i"
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strippedEdgeJunk(_ value: String) -> String {
        var start = value.startIndex
        while start < value.endIndex, !containsAlphanumeric(value[start]) {
            start = value.index(after: start)
        }

        var end = value.endIndex
        while start < end {
            let previous = value.index(before: end)
            let character = value[previous]
            if containsAlphanumeric(character) || allowedTrailingCharacters.contains(character) {
                break
            }
            end = previous
        }

        return String(value[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dedupeKey(_ value: String) -> String {
        let lowered = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> String in
            if isLetter(scalar) || isDigit(scalar) {
                return String(scalar)
            }
            return " "
        }.joined()
        return normalizedWhitespace(scalars)
    }

    private static func containsAlphanumeric(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            isLetter(scalar) || isDigit(scalar)
        }
    }

    private static func isLetter(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.letters.contains(scalar)
    }

    private static func isDigit(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.decimalDigits.contains(scalar)
    }
}
