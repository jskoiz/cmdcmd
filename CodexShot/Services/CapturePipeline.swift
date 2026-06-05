import Foundation
import OSLog

private let capturePipelineLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.jskoiz.CodexShot",
    category: "CapturePipeline"
)

enum CapturePipeline {
    static func submit(
        imageData originalImageData: Data,
        filename: String = "screenshot.png",
        note: String,
        source: CaptureSource,
        sourceDetail: String = ""
    ) async -> CaptureRecord {
        let startedAt = Date()
        let settings = CaptureRepository.loadSettings()
        let endpointHost = URL(string: settings.endpoint)?.host()
        capturePipelineLogger.info(
            "submit started source=\(source.rawValue, privacy: .public) originalBytes=\(originalImageData.count, privacy: .public) endpointHost=\(endpointHost ?? "none", privacy: .public) includeOCR=\(settings.includeRecognizedText, privacy: .public) noteChars=\(note.count, privacy: .public)"
        )

        let uploadData = ImageProcessor.normalizedUploadData(from: originalImageData)
        capturePipelineLogger.info(
            "image normalized uploadBytes=\(uploadData.count, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
        )

        let recognizedText: String
        if settings.includeRecognizedText {
            let ocrStartedAt = Date()
            capturePipelineLogger.info("ocr started uploadBytes=\(uploadData.count, privacy: .public)")
            recognizedText = await OCRService.recognizedText(from: uploadData)
            capturePipelineLogger.info(
                "ocr finished recognizedTextChars=\(recognizedText.count, privacy: .public) durationMs=\(elapsedMilliseconds(since: ocrStartedAt), privacy: .public)"
            )
        } else {
            recognizedText = ""
            capturePipelineLogger.info("ocr skipped")
        }

        let context = [settings.defaultContext, note]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        var record = CaptureRecord(
            source: source,
            sourceDetail: sourceDetail,
            userNote: note,
            recognizedText: recognizedText,
            status: .sending,
            statusMessage: "Preparing upload",
            endpointHost: endpointHost,
            imageFilename: filename,
            thumbnailData: ImageProcessor.thumbnailData(from: originalImageData)
        )
        CaptureRepository.upsert(record)
        capturePipelineLogger.info(
            "record upserted captureId=\(record.id.uuidString, privacy: .public) contextChars=\(context.count, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
        )

        let payload = CaptureUploadPayload(
            schemaVersion: 1,
            captureId: record.id,
            createdAt: record.createdAt,
            source: source.rawValue,
            sourceDetail: sourceDetail,
            context: context,
            recognizedText: recognizedText,
            imageFilename: filename,
            imageMimeType: ImageProcessor.mimeType(for: uploadData, filename: filename),
            imageBase64: uploadData.base64EncodedString()
        )

        do {
            capturePipelineLogger.info(
                "relay send started captureId=\(record.id.uuidString, privacy: .public) endpointHost=\(endpointHost ?? "none", privacy: .public)"
            )
            let relayClient = RelayClient(settings: settings)
            let sendResult = try await relayClient.send(payload)
            record.status = .sent
            record.statusMessage = queuedMessage()
            CaptureRepository.upsert(record)
            capturePipelineLogger.info(
                "submit accepted captureId=\(record.id.uuidString, privacy: .public) relayStatus=\(sendResult.status, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
            )
            do {
                if let deliveryStatus = try await relayClient.waitForDeliveryStatus(after: sendResult) {
                    applyDeliveryStatus(deliveryStatus, to: &record, fallbackQueuedMessage: queuedMessage())
                }
            } catch {
                capturePipelineLogger.error(
                    "delivery status polling failed captureId=\(record.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
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
            record.statusMessage = error.localizedDescription
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

    private static func queuedMessage() -> String {
        "Queued"
    }

    private static func applyDeliveryStatus(
        _ deliveryStatus: RelayDeliveryStatus,
        to record: inout CaptureRecord,
        fallbackQueuedMessage: String
    ) {
        switch deliveryStatus.status {
        case "delivered":
            record.status = .sent
            record.statusMessage = deliveryStatus.message
        case "failed":
            record.status = .failed
            record.statusMessage = deliveryStatus.message
        default:
            record.status = .sent
            record.statusMessage = deliveryStatus.message.isEmpty ? fallbackQueuedMessage : deliveryStatus.message
        }
    }
}

private func elapsedMilliseconds(since date: Date) -> Int {
    Int(Date().timeIntervalSince(date) * 1000)
}
