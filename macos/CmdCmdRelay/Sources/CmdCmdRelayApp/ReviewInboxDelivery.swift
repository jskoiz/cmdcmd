import AppKit
import Foundation

enum ReviewInboxDelivery {
    typealias OpenInboxHandler = (URL) -> Void

    private static let lock = NSLock()

    static func deliver(
        capture: CapturePayload,
        stored: StoredCapture,
        settings: RelaySettings,
        openInboxHandler: OpenInboxHandler = { openInbox($0) }
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let inboxURL = URL(fileURLWithPath: settings.inboxDirectory, isDirectory: true)
            .appendingPathComponent("review-inbox", isDirectory: true)
        let capturesURL = inboxURL.appendingPathComponent("captures", isDirectory: true)
        try FileManager.default.createDirectory(
            at: capturesURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let manifestURL = inboxURL.appendingPathComponent("captures.json")
        var entries = try loadEntries(from: manifestURL)
        let assetURL = capturesURL.appendingPathComponent("\(capture.captureId).\(extensionName(for: capture))")
        try capture.imageData.write(to: assetURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: assetURL.path)
        entries.removeAll { $0.captureId == capture.captureId }
        entries.insert(ReviewInboxEntry(capture: capture, stored: stored, assetURL: assetURL), at: 0)
        let evictedEntries: [ReviewInboxEntry]
        if entries.count > 50 {
            evictedEntries = Array(entries.dropFirst(50))
            entries = Array(entries.prefix(50))
        } else {
            evictedEntries = []
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: manifestURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)

        let indexURL = inboxURL.appendingPathComponent("index.html")
        try renderHTML(entries: entries).write(to: indexURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)

        try deleteManagedAssets(for: evictedEntries, in: capturesURL)
        openInboxHandler(indexURL)
    }

    private static func loadEntries(from url: URL) throws -> [ReviewInboxEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ReviewInboxEntry].self, from: data)
        } catch {
            throw RelayHTTPError.server(
                "Review inbox history is unreadable. The existing history was preserved."
            )
        }
    }

    private static func extensionName(for capture: CapturePayload) -> String {
        capture.imageMimeType == "image/jpeg" ? "jpg" : "png"
    }

    private static func deleteManagedAssets(for entries: [ReviewInboxEntry], in capturesURL: URL) throws {
        let managedDirectory = capturesURL.standardizedFileURL
        for entry in entries {
            let filename = entry.assetFilename
            guard !filename.isEmpty,
                  URL(fileURLWithPath: filename).lastPathComponent == filename else {
                continue
            }

            let assetURL = capturesURL.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
            guard assetURL.deletingLastPathComponent() == managedDirectory,
                  FileManager.default.fileExists(atPath: assetURL.path) else {
                continue
            }
            try FileManager.default.removeItem(at: assetURL)
        }
    }

    private static func openInbox(_ url: URL) {
        guard ProcessInfo.processInfo.environment["CMDCMD_REVIEW_INBOX_OPEN"] != "0" else {
            return
        }

        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }

    private static func renderHTML(entries: [ReviewInboxEntry]) -> String {
        guard let latest = entries.first else {
            return baseHTML(title: "cmd+cmd Review Inbox", body: "<p>No captures yet.</p>")
        }

        let history = entries.map { entry in
            """
            <li>
              <a href="captures/\(escapeAttribute(entry.assetFilename))">\(escapeHTML(entry.captureId))</a>
              <span>\(escapeHTML(entry.receivedAt))</span>
            </li>
            """
        }.joined(separator: "\n")

        let sourceDetail = latest.sourceDetail.isEmpty ? "" : " / \(latest.sourceDetail)"
        let visibleApp = latest.visibleAppName.map { "<dt>Visible app</dt><dd>\(escapeHTML($0))</dd>" } ?? ""
        let context = latest.context.isEmpty ? "" : """
        <section>
          <h2>Context</h2>
          <pre>\(escapeHTML(latest.context))</pre>
        </section>
        """
        let ocr = latest.recognizedText.isEmpty ? "" : """
        <section>
          <h2>Recognized Text</h2>
          <pre>\(escapeHTML(latest.recognizedText))</pre>
        </section>
        """

        return baseHTML(
            title: "cmd+cmd Review Inbox",
            body: """
            <header>
              <p class="mark">cmd+cmd</p>
              <h1>Review Inbox</h1>
              <p class="muted">Review mode received this screenshot on this Mac. Codex Desktop is not required.</p>
            </header>
            <main>
              <section class="shot">
                <img src="captures/\(escapeAttribute(latest.assetFilename))" alt="Latest screenshot" />
              </section>
              <section>
                <h2>Latest Capture</h2>
                <dl>
                  <dt>Capture ID</dt><dd>\(escapeHTML(latest.captureId))</dd>
                  <dt>Received</dt><dd>\(escapeHTML(latest.receivedAt))</dd>
                  <dt>Created</dt><dd>\(escapeHTML(latest.createdAt))</dd>
                  <dt>Source</dt><dd>\(escapeHTML(latest.source + sourceDetail))</dd>
                  <dt>Image</dt><dd>\(escapeHTML(latest.imageSizeLabel))</dd>
                  <dt>Stored file</dt><dd>\(escapeHTML(latest.originalImagePath))</dd>
                  \(visibleApp)
                </dl>
              </section>
              \(context)
              \(ocr)
              <section>
                <h2>Recent Captures</h2>
                <ol class="history">
                  \(history)
                </ol>
              </section>
            </main>
            """
        )
    }

    private static func baseHTML(title: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>\(escapeHTML(title))</title>
            <style>
              :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
              body { margin: 0; background: #fff; color: #111; }
              header, main { width: min(920px, calc(100vw - 48px)); margin: 0 auto; }
              header { padding: 48px 0 24px; border-bottom: 1px solid #e6e6e6; }
              .mark { margin: 0 0 32px; font: 700 18px/1.1 ui-monospace, SFMono-Regular, Menlo, monospace; }
              h1 { margin: 0 0 12px; font-size: clamp(36px, 8vw, 72px); letter-spacing: 0; line-height: .92; }
              h2 { margin: 0 0 16px; font-size: 18px; letter-spacing: 0; }
              .muted, dd, li span { color: #777; }
              main { padding: 28px 0 56px; }
              section { padding: 24px 0; border-bottom: 1px solid #eaeaea; }
              .shot { display: flex; justify-content: center; background: #fafafa; border: 1px solid #eee; padding: 18px; }
              img { max-width: 100%; max-height: 72vh; object-fit: contain; }
              dl { display: grid; grid-template-columns: 140px minmax(0, 1fr); gap: 10px 18px; margin: 0; }
              dt { font-weight: 700; }
              dd { margin: 0; overflow-wrap: anywhere; }
              pre { margin: 0; padding: 16px; white-space: pre-wrap; overflow-wrap: anywhere; background: #f7f7f7; border: 1px solid #eee; }
              .history { margin: 0; padding-left: 22px; }
              .history li { margin: 8px 0; }
              a { color: #111; }
              @media (max-width: 640px) {
                header, main { width: min(100vw - 28px, 920px); }
                dl { grid-template-columns: 1fr; }
              }
            </style>
          </head>
          <body>
            \(body)
          </body>
        </html>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeHTML(value)
    }
}

private struct ReviewInboxEntry: Codable {
    var captureId: String
    var receivedAt: String
    var createdAt: String
    var source: String
    var sourceDetail: String
    var context: String
    var recognizedText: String
    var assetFilename: String
    var originalImagePath: String
    var metadataPath: String
    var pixelWidth: Int?
    var pixelHeight: Int?
    var visibleAppName: String?

    init(capture: CapturePayload, stored: StoredCapture, assetURL: URL) {
        captureId = capture.captureId
        receivedAt = ISO8601DateFormatter().string(from: Date())
        createdAt = capture.createdAt
        source = capture.source
        sourceDetail = capture.sourceDetail
        context = capture.context
        recognizedText = capture.recognizedText
        assetFilename = assetURL.lastPathComponent
        originalImagePath = stored.imagePath
        metadataPath = stored.metadataPath
        pixelWidth = capture.screenshotContext.pixelWidth
        pixelHeight = capture.screenshotContext.pixelHeight
        visibleAppName = capture.screenshotContext.visibleApp?.name
    }

    var imageSizeLabel: String {
        guard let pixelWidth, let pixelHeight else {
            return "Screenshot"
        }
        return "\(pixelWidth) x \(pixelHeight) px"
    }
}
