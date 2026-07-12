import Foundation
import OSLog

private let capturePipelineLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.jskoiz.CmdCmd",
    category: "CapturePipeline"
)

enum CapturePipeline {
    static func submit(
        imageData originalImageData: Data,
        filename: String = "screenshot.png",
        note: String,
        source: CaptureSource,
        sourceDetail: String = "",
        imageMetadata: CaptureImageMetadata = .empty
    ) async throws -> CaptureRecord {
        let startedAt = Date()
        let settings = CaptureRepository.loadSettings()
        let endpointHost = URL(string: settings.endpoint)?.host()
        capturePipelineLogger.info(
            "submit started source=\(source.rawValue, privacy: .public) originalBytes=\(originalImageData.count, privacy: .public) endpointHost=\(endpointHost ?? "none", privacy: .public) includeOCR=\(settings.includeRecognizedText, privacy: .public) noteChars=\(note.count, privacy: .public)"
        )

        let preparedImage: PreparedImage
        do {
            preparedImage = try ImageProcessor.prepare(data: originalImageData, filename: filename)
        } catch {
            let record = CaptureRecord(
                source: source,
                sourceDetail: sourceDetail,
                userNote: note,
                recognizedText: "",
                status: .failed,
                statusMessage: error.localizedDescription,
                endpointHost: endpointHost,
                imageFilename: filename,
                thumbnailData: nil
            )
            CaptureRepository.upsert(record)
            capturePipelineLogger.error(
                "image preparation failed captureId=\(record.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return record
        }
        capturePipelineLogger.info(
            "image prepared uploadBytes=\(preparedImage.data.count, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
        )

        let ocrReport: OCRReport
        if settings.includeRecognizedText {
            let ocrStartedAt = Date()
            capturePipelineLogger.info("ocr started uploadBytes=\(preparedImage.data.count, privacy: .public)")
            ocrReport = try await OCRService.report(from: preparedImage.data)
            capturePipelineLogger.info(
                "ocr finished recognizedTextChars=\(ocrReport.characterCount, privacy: .public) lines=\(ocrReport.lineCount, privacy: .public) durationMs=\(elapsedMilliseconds(since: ocrStartedAt), privacy: .public)"
            )
        } else {
            ocrReport = .skipped
            capturePipelineLogger.info("ocr skipped")
        }
        let recognizedText = ocrReport.text

        let context = [settings.defaultContext, note]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let visibleApp = VisibleAppInferer.infer(from: recognizedText)
        let screenshotContext = ScreenshotContext(
            capturedAt: imageMetadata.capturedAt,
            preparedAt: .now,
            timeZoneIdentifier: TimeZone.current.identifier,
            source: source.rawValue,
            sourceDetail: sourceDetail,
            imageFilename: preparedImage.filename,
            imageMimeType: preparedImage.mimeType,
            pixelWidth: preparedImage.pixelWidth,
            pixelHeight: preparedImage.pixelHeight,
            originalImageBytes: originalImageData.count,
            uploadImageBytes: preparedImage.data.count,
            ocrEnabled: settings.includeRecognizedText,
            ocrDurationMs: settings.includeRecognizedText ? ocrReport.durationMs : nil,
            ocrLineCount: ocrReport.lineCount,
            ocrCharacterCount: ocrReport.characterCount,
            ocrTimedOut: ocrReport.timedOut,
            ocrAverageConfidence: ocrReport.averageConfidence,
            visibleApp: visibleApp
        )

        var record = CaptureRecord(
            source: source,
            sourceDetail: sourceDetail,
            userNote: note,
            recognizedText: recognizedText,
            status: .sending,
            statusMessage: "Preparing upload",
            endpointHost: endpointHost,
            imageFilename: preparedImage.filename,
            thumbnailData: preparedImage.thumbnailData
        )
        CaptureRepository.upsert(record)
        capturePipelineLogger.info(
            "record upserted captureId=\(record.id.uuidString, privacy: .public) contextChars=\(context.count, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
        )

        let payload = CaptureUploadPayload(
            schemaVersion: 2,
            captureId: record.id,
            createdAt: record.createdAt,
            source: source.rawValue,
            sourceDetail: sourceDetail,
            screenshotContext: screenshotContext,
            context: context,
            recognizedText: recognizedText,
            imageFilename: preparedImage.filename,
            imageMimeType: preparedImage.mimeType,
            imageBase64: preparedImage.data.base64EncodedString()
        )

        do {
            capturePipelineLogger.info(
                "relay send started captureId=\(record.id.uuidString, privacy: .public) endpointHost=\(endpointHost ?? "none", privacy: .public)"
            )
            let relayClient = RelayClient(settings: settings)
            let sendResult = try await relayClient.send(payload)
            record.status = .sending
            record.statusMessage = queuedMessage()
            CaptureRepository.upsert(record)
            capturePipelineLogger.info(
                "submit accepted captureId=\(record.id.uuidString, privacy: .public) relayStatus=\(sendResult.status, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
            )
            do {
                if let deliveryStatus = try await relayClient.waitForDeliveryStatus(after: sendResult) {
                    if deliveryStatus.isTerminal {
                        applyDeliveryStatus(deliveryStatus, to: &record, fallbackQueuedMessage: queuedMessage())
                    } else {
                        record.status = .sending
                        record.statusMessage = unconfirmedDeliveryMessage()
                    }
                } else {
                    record.status = .sending
                    record.statusMessage = unconfirmedDeliveryMessage()
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                capturePipelineLogger.error(
                    "delivery status polling failed captureId=\(record.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                record.status = .sending
                record.statusMessage = unconfirmedDeliveryMessage()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch RelayClientError.missingEndpoint {
            record.status = .needsEndpoint
            record.statusMessage = RelayClientError.missingEndpoint.localizedDescription
            capturePipelineLogger.error("submit missing endpoint captureId=\(record.id.uuidString, privacy: .public)")
        } catch RelayClientError.invalidEndpoint {
            record.status = .failed
            record.statusMessage = RelayClientError.invalidEndpoint.localizedDescription
            capturePipelineLogger.error("submit invalid endpoint captureId=\(record.id.uuidString, privacy: .public)")
        } catch {
            record.status = .failed
            record.statusMessage = userFacingFailureMessage(for: error, settings: settings)
            capturePipelineLogger.error(
                "submit failed captureId=\(record.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
            )
        }

        CaptureRepository.upsert(record)
        capturePipelineLogger.info(
            "record finalized captureId=\(record.id.uuidString, privacy: .public) status=\(record.status.rawValue, privacy: .public) message=\(record.statusMessage, privacy: .public)"
        )
        return record
    }

    static var deliveredStatusMessage: String {
        "Screenshot sent to Codex"
    }

    private static func queuedMessage() -> String {
        "Screenshot queued for Codex"
    }

    private static func unconfirmedDeliveryMessage() -> String {
        "Screenshot reached the relay, but delivery to Codex wasn't confirmed. Check Codex Desktop for the screenshot."
    }

    private static func userFacingFailureMessage(for error: Error, settings: RelaySettings) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           [
               NSURLErrorTimedOut,
               NSURLErrorCannotFindHost,
               NSURLErrorCannotConnectToHost,
               NSURLErrorNetworkConnectionLost,
               NSURLErrorNotConnectedToInternet
           ].contains(nsError.code),
           endpointUsesLocalNetwork(settings.endpoint) {
            return CaptureFailurePresentation.relayReachabilityMessage(endpoint: settings.endpoint)
        }

        return error.localizedDescription
    }

    private static func endpointUsesLocalNetwork(_ endpoint: String) -> Bool {
        guard let host = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host()?.lowercased() else {
            return false
        }

        if host == "localhost" || host.hasSuffix(".local") {
            return true
        }

        if host.hasPrefix("10.") || host.hasPrefix("192.168.") {
            return true
        }

        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }

        return false
    }

    private static func applyDeliveryStatus(
        _ deliveryStatus: RelayDeliveryStatus,
        to record: inout CaptureRecord,
        fallbackQueuedMessage: String
    ) {
        switch deliveryStatus.status {
        case "delivered":
            record.status = .sent
            record.statusMessage = deliveredStatusMessage
        case "failed":
            record.status = .failed
            record.statusMessage = deliveryStatus.message
        default:
            record.status = .sending
            record.statusMessage = deliveryStatus.message.isEmpty ? fallbackQueuedMessage : deliveryStatus.message
        }
    }
}

private enum VisibleAppInferer {
    private struct Rule {
        var name: String
        var threshold: Int
        var signals: [String]
    }

    private struct Match {
        var rule: Rule
        var evidence: [String]

        var score: Int {
            evidence.count
        }
    }

    private static let rules = [
        Rule(name: "Photos", threshold: 3, signals: [
            "Library",
            "Collections",
            "Syncing Paused",
            "Select",
            "Albums",
            "Recents"
        ]),
        Rule(name: "Settings", threshold: 2, signals: [
            "Wi-Fi",
            "Bluetooth",
            "Cellular",
            "Notifications",
            "General",
            "Apple Account"
        ]),
        Rule(name: "Messages", threshold: 2, signals: [
            "iMessage",
            "Text Message",
            "Messages",
            "Delivered"
        ]),
        Rule(name: "Safari", threshold: 2, signals: [
            "Search or enter website name",
            "Reader",
            "Private",
            "Tabs"
        ]),
        Rule(name: "Mail", threshold: 2, signals: [
            "Inbox",
            "Unread",
            "Flagged",
            "Compose"
        ]),
        Rule(name: "Stripe", threshold: 2, signals: [
            "Stripe Express",
            "Payouts",
            "Payments",
            "Connect",
            "Dashboard"
        ]),
        Rule(name: "cmd+cmd", threshold: 2, signals: [
            "Send to Codex",
            "OCR ready",
            "Thread hint",
            "Private relay"
        ]),
        Rule(name: "CIRCA", threshold: 2, signals: [
            "Waiting on CIRCA",
            "Buyer pays",
            "Seller tools",
            "Unlock seller tools"
        ])
    ]

    static func infer(from text: String) -> VisibleAppContext? {
        let normalizedText = normalize(text)
        guard !normalizedText.isEmpty else {
            return nil
        }

        let matches = rules.compactMap { rule -> Match? in
            let evidence = rule.signals.filter { signal in
                normalizedText.contains(normalize(signal))
            }
            guard evidence.count >= rule.threshold else {
                return nil
            }
            return Match(rule: rule, evidence: evidence)
        }

        guard let best = matches.sorted(by: { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.rule.threshold > rhs.rule.threshold
            }
            return lhs.score > rhs.score
        }).first else {
            return nil
        }

        return VisibleAppContext(
            name: best.rule.name,
            confidence: best.score >= best.rule.threshold + 1 ? "high" : "medium",
            evidence: Array(best.evidence.prefix(4))
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
