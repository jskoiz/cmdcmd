import Foundation

enum CapturePipeline {
    static func submit(
        imageData originalImageData: Data,
        filename: String = "screenshot.png",
        note: String,
        source: CaptureSource,
        sourceDetail: String = ""
    ) async -> CaptureRecord {
        let settings = CaptureRepository.loadSettings()
        let uploadData = ImageProcessor.normalizedUploadData(from: originalImageData)
        let recognizedText = settings.includeRecognizedText ? await OCRService.recognizedText(from: uploadData) : ""
        let context = [settings.defaultContext, note]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let endpointHost = URL(string: settings.endpoint)?.host()
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

        let payload = CaptureUploadPayload(
            schemaVersion: 1,
            captureId: record.id,
            createdAt: record.createdAt,
            source: source.rawValue,
            sourceDetail: sourceDetail,
            context: context,
            recognizedText: recognizedText,
            threadHint: settings.threadHint,
            imageFilename: filename,
            imageMimeType: ImageProcessor.mimeType(for: uploadData, filename: filename),
            imageBase64: uploadData.base64EncodedString()
        )

        do {
            try await RelayClient(settings: settings).send(payload)
            record.status = .sent
            record.statusMessage = "Delivered"
        } catch RelayClientError.missingEndpoint {
            record.status = .needsEndpoint
            record.statusMessage = RelayClientError.missingEndpoint.localizedDescription
        } catch RelayClientError.invalidEndpoint {
            record.status = .failed
            record.statusMessage = RelayClientError.invalidEndpoint.localizedDescription
        } catch {
            record.status = .failed
            record.statusMessage = error.localizedDescription
        }

        CaptureRepository.upsert(record)
        return record
    }
}

