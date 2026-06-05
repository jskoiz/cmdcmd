import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum DesktopDelivery {
    static func deliver(capture: CapturePayload, stored: StoredCapture, settings: RelaySettings) throws {
        try requireAccessibilityTrust()

        if settings.openImageInViewer {
            openImage(path: stored.imagePath, bundleIdentifier: settings.viewerBundleIdentifier)
            Thread.sleep(forTimeInterval: 0.75)
        }

        try copyImageToPasteboard(stored.imagePath)
        guard let codex = launchOrActivate(bundleIdentifier: settings.codexBundleIdentifier) else {
            throw RelayHTTPError.server("Could not activate Codex app bundle \(settings.codexBundleIdentifier).")
        }

        Thread.sleep(forTimeInterval: Double(settings.pasteDelayMilliseconds) / 1000.0)
        try pasteIntoCodex(app: codex, text: attachmentText(capture: capture), composerBottomOffset: 70)

        if settings.openImageInViewer, settings.closeViewerWindow {
            closeViewerWindow(
                imagePath: stored.imagePath,
                viewerBundleIdentifier: settings.viewerBundleIdentifier,
                codex: codex
            )
        }
    }

    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: prompt] as CFDictionary)
    }

    private static func requireAccessibilityTrust() throws {
        guard accessibilityTrusted(prompt: true) else {
            throw RelayHTTPError.server(
                "Accessibility permission is required to focus Codex and paste the screenshot. Grant Accessibility permission to cmd+cmd Relay, then retry."
            )
        }
    }

    private static func openImage(path: String, bundleIdentifier: String) {
        let imageURL = URL(fileURLWithPath: path)
        guard let viewerURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSWorkspace.shared.open(imageURL)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([imageURL], withApplicationAt: viewerURL, configuration: configuration)
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

    private static func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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

    private static func pasteIntoCodex(
        app: NSRunningApplication,
        text: String?,
        composerBottomOffset: Int
    ) throws {
        let source = try eventSource()
        let frame = try focusedWindowFrame(for: app)
        let clickPoint = CGPoint(
            x: frame.origin.x + frame.width / 2,
            y: frame.origin.y + frame.height - CGFloat(composerBottomOffset)
        )

        postKey(source, key: 53, down: true)
        postKey(source, key: 53, down: false)
        usleep(100_000)
        try postClick(source, point: clickPoint)
        usleep(150_000)
        try postPaste(source)

        if let text, !text.isEmpty {
            usleep(300_000)
            copyTextToPasteboard(text)
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
        let sections = [
            screenshotContextText(capture.screenshotContext),
            capture.context.isEmpty ? nil : "Context:\n\(capture.context)",
            capture.recognizedText.isEmpty ? nil : "OCR text:\n\(capture.recognizedText)"
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private static func screenshotContextText(_ context: ScreenshotContext) -> String? {
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
        if context.ocrEnabled {
            lines.append("OCR: \(context.ocrLineCount) lines, \(context.ocrCharacterCount) characters")
        } else {
            lines.append("OCR: off")
        }

        return "Screenshot context:\n\(lines.joined(separator: "\n"))"
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

    private static func closeViewerWindow(
        imagePath: String,
        viewerBundleIdentifier: String,
        codex: NSRunningApplication
    ) {
        guard let viewer = runningApplication(bundleIdentifier: viewerBundleIdentifier) else {
            return
        }
        let viewerElement = AXUIElementCreateApplication(viewer.processIdentifier)
        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(
            viewerElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        guard windowsResult == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            return
        }

        let imageURL = URL(fileURLWithPath: imagePath)
        let fileName = imageURL.lastPathComponent
        let fileStem = imageURL.deletingPathExtension().lastPathComponent
        let targetWindow = windows.first { window in
            let windowTitle = title(for: window)
            return windowTitle.contains(fileName) || windowTitle.contains(fileStem)
        } ?? windows[0]

        focusViewerWindow(appElement: viewerElement, window: targetWindow)
        activate(viewer)
        usleep(100_000)

        if let closeButton = closeButton(for: targetWindow),
           AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success {
            usleep(150_000)
            activate(codex)
            return
        }
    }

    private static func title(for window: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        guard result == .success, let title = titleRef as? String else {
            return ""
        }
        return title
    }

    private static func closeButton(for window: AXUIElement) -> AXUIElement? {
        var closeButtonRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeButtonRef)
        guard result == .success, closeButtonRef != nil else {
            return nil
        }
        return (closeButtonRef as! AXUIElement)
    }

    private static func focusViewerWindow(appElement: AXUIElement, window: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
