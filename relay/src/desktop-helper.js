import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

export const DESKTOP_HELPER_VERSION = "2026-06-05.7";

export async function ensureDesktopHelper(options = {}) {
  const cacheDir =
    options.cacheDir ??
    path.join(os.homedir(), "Library", "Caches", "cmdcmd-relay");
  const helperPath = path.join(cacheDir, "cmdcmd-desktop-helper");
  const sourcePath = path.join(cacheDir, "cmdcmd-desktop-helper.swift");
  const versionPath = path.join(cacheDir, "desktop-helper.version");

  if (await helperIsCurrent(helperPath, versionPath)) {
    return helperPath;
  }

  await fs.mkdir(cacheDir, { recursive: true });
  await fs.writeFile(sourcePath, DESKTOP_HELPER_SOURCE);
  await options.runCommand(
    "/usr/bin/swiftc",
    [
      sourcePath,
      "-o",
      helperPath,
      "-framework",
      "AppKit",
      "-framework",
      "ApplicationServices",
      "-framework",
      "CoreGraphics"
    ],
    { timeoutMs: options.compileTimeoutMs ?? 30000 }
  );
  await fs.writeFile(versionPath, DESKTOP_HELPER_VERSION);
  return helperPath;
}

async function helperIsCurrent(helperPath, versionPath) {
  try {
    const [helperStat, version] = await Promise.all([
      fs.stat(helperPath),
      fs.readFile(versionPath, "utf8")
    ]);
    return helperStat.mode & 0o111 && version.trim() === DESKTOP_HELPER_VERSION;
  } catch {
    return false;
  }
}

const DESKTOP_HELPER_SOURCE = String.raw`import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct Config {
    var imagePath: String?
    var contextPath: String?
    var codexBundle = "com.openai.codex"
    var focusDelayMs = 400
    var composerBottomOffset = 70
    var dryRun = false
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    fputs("cmdcmd-desktop-helper: \(message)\n", stderr)
    exit(code)
}

func parsePositiveInt(_ value: String, name: String) -> Int {
    guard let parsed = Int(value), parsed > 0 else {
        fail("invalid \(name): \(value)", code: 64)
    }
    return parsed
}

func parseArgs() -> Config {
    var config = Config()
    var index = 1
    let args = CommandLine.arguments

    func takeValue(_ option: String) -> String {
        guard index + 1 < args.count else {
            fail("missing value for \(option)", code: 64)
        }
        index += 1
        return args[index]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--image-path":
            config.imagePath = takeValue(arg)
        case "--context-path":
            config.contextPath = takeValue(arg)
        case "--codex-bundle":
            config.codexBundle = takeValue(arg)
        case "--focus-delay-ms":
            config.focusDelayMs = parsePositiveInt(takeValue(arg), name: arg)
        case "--composer-bottom-offset":
            config.composerBottomOffset = parsePositiveInt(takeValue(arg), name: arg)
        case "--dry-run":
            config.dryRun = true
        default:
            fail("unknown option: \(arg)", code: 64)
        }
        index += 1
    }

    return config
}

func requireAccessibilityTrust() {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    if !trusted {
        fail("Accessibility permission is required on your Mac. Grant it to the relay helper, then try again.", code: 77)
    }
}

func runningApp(bundleID: String) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
}

func launchOrActivate(bundleID: String) -> NSRunningApplication? {
    if let app = runningApp(bundleID: bundleID) {
        _ = app.activate(options: [.activateIgnoringOtherApps])
        return app
    }

    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
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
    return box.app ?? runningApp(bundleID: bundleID)
}

func copyImageToPasteboard(_ imagePath: String) {
    guard let image = NSImage(contentsOfFile: imagePath) else {
        fail("could not load image: \(imagePath)", code: 66)
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    if pasteboard.writeObjects([image]) {
        return
    }

    guard let tiff = image.tiffRepresentation else {
        fail("could not encode image for pasteboard", code: 70)
    }
    pasteboard.setData(tiff, forType: .tiff)
}

func copyFileToPasteboard(_ filePath: String) {
    let url = URL(fileURLWithPath: filePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
        fail("could not find context attachment: \(filePath)", code: 66)
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    if pasteboard.writeObjects([url as NSURL]) {
        return
    }
    pasteboard.setString(url.absoluteString, forType: .fileURL)
}

func focusedWindowFrame(for app: NSRunningApplication) -> CGRect {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    var windowsRef: CFTypeRef?
    let windowsResult = AXUIElementCopyAttributeValue(
        element,
        kAXWindowsAttribute as CFString,
        &windowsRef
    )
    guard windowsResult == .success, let windows = windowsRef as? [AXUIElement], let window = windows.first else {
        fail("could not read Codex window bounds", code: 70)
    }

    var positionRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    let positionResult = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
    let sizeResult = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
    guard
        positionResult == .success,
        sizeResult == .success,
        let positionValue = positionRef,
        let sizeValue = sizeRef
    else {
        fail("could not read Codex window frame", code: 70)
    }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else {
        fail("could not decode Codex window frame", code: 70)
    }

    return CGRect(origin: position, size: size)
}

func eventSource() -> CGEventSource {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
        fail("could not create event source", code: 70)
    }
    source.localEventsSuppressionInterval = 0
    return source
}

func postKey(_ source: CGEventSource, key: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
        fail("could not create keyboard event", code: 70)
    }
    event.flags = flags
    event.post(tap: .cghidEventTap)
    usleep(30_000)
}

func postPaste(_ source: CGEventSource) {
    postKey(source, key: 55, down: true, flags: .maskCommand)
    postKey(source, key: 9, down: true, flags: .maskCommand)
    postKey(source, key: 9, down: false, flags: .maskCommand)
    postKey(source, key: 55, down: false)
}

func postClick(_ source: CGEventSource, point: CGPoint) {
    guard
        let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    else {
        fail("could not create mouse event", code: 70)
    }

    move.post(tap: .cghidEventTap)
    usleep(30_000)
    down.post(tap: .cghidEventTap)
    usleep(30_000)
    up.post(tap: .cghidEventTap)
    usleep(30_000)
}

func pasteIntoCodex(app: NSRunningApplication, config: Config) {
    guard let imagePath = config.imagePath else {
        fail("--image-path is required", code: 64)
    }

    let source = eventSource()
    let frame = focusedWindowFrame(for: app)
    let clickPoint = CGPoint(
        x: frame.origin.x + (frame.width / 2),
        y: frame.origin.y + frame.height - CGFloat(config.composerBottomOffset)
    )

    postKey(source, key: 53, down: true)
    postKey(source, key: 53, down: false)
    usleep(100_000)
    postClick(source, point: clickPoint)
    usleep(150_000)

    copyImageToPasteboard(imagePath)
    postPaste(source)

    if let contextPath = config.contextPath {
        usleep(300_000)
        copyFileToPasteboard(contextPath)
        postPaste(source)
    }
}

let config = parseArgs()
guard let imagePath = config.imagePath else {
    fail("--image-path is required", code: 64)
}

if config.dryRun {
    print("Codex: \(config.codexBundle)")
    print("Image: \(imagePath)")
    print("Context attachment: \(config.contextPath ?? "(none)")")
    print("Focus delay: \(config.focusDelayMs)ms")
    print("Would open viewer: no")
    print("Would paste inline text: no")
    exit(0)
}

requireAccessibilityTrust()
guard let codex = launchOrActivate(bundleID: config.codexBundle) else {
    fail("could not activate Codex app bundle \(config.codexBundle)", code: 69)
}

Thread.sleep(forTimeInterval: Double(config.focusDelayMs) / 1000.0)
pasteIntoCodex(app: codex, config: config)
print("Screenshot sent to Codex.")
`;
