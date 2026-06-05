import Foundation
import OSLog
import UIKit
import Vision

private let ocrLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.jskoiz.CmdCmd",
    category: "OCRService"
)

enum OCRService {
    static func report(from imageData: Data) async -> OCRReport {
        let startedAt = Date()
        ocrLogger.info("recognition task group started imageBytes=\(imageData.count, privacy: .public)")

        return await withTaskGroup(of: OCRResult.self) { group in
            group.addTask {
                .recognized(await performRecognition(from: imageData))
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                return .timedOut
            }

            let result = await group.next() ?? .recognized(
                RecognizedTextPayload(lines: [], averageConfidence: nil)
            )
            group.cancelAll()
            switch result {
            case .recognized(let payload):
                let durationMs = elapsedMilliseconds(since: startedAt)
                let text = payload.lines.joined(separator: "\n")
                ocrLogger.info(
                    "recognition task group completed textChars=\(text.count, privacy: .public) lines=\(payload.lines.count, privacy: .public) durationMs=\(durationMs, privacy: .public)"
                )
                return OCRReport(
                    text: text,
                    durationMs: durationMs,
                    lineCount: payload.lines.count,
                    characterCount: text.count,
                    timedOut: false,
                    averageConfidence: payload.averageConfidence
                )
            case .timedOut:
                let durationMs = elapsedMilliseconds(since: startedAt)
                ocrLogger.error(
                    "recognition timed out durationMs=\(durationMs, privacy: .public)"
                )
                return OCRReport(
                    text: "",
                    durationMs: durationMs,
                    lineCount: 0,
                    characterCount: 0,
                    timedOut: true,
                    averageConfidence: nil
                )
            }
        }
    }

    private static func performRecognition(from imageData: Data) async -> RecognizedTextPayload {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
                ocrLogger.error("recognition failed to decode image")
                return RecognizedTextPayload(lines: [], averageConfidence: nil)
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.012

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImageOrientation)

            do {
                try handler.perform([request])
            } catch {
                ocrLogger.error("vision request failed error=\(error.localizedDescription, privacy: .public)")
                return RecognizedTextPayload(lines: [], averageConfidence: nil)
            }

            let observations = request.results ?? []
            let candidates = observations
                .sorted { lhs, rhs in
                    if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                .compactMap { observation -> VNRecognizedText? in
                    observation.topCandidates(1).first
                }
                .filter { candidate in
                    candidate.confidence >= 0.35
                }
            let lines = candidates.map(\.string)
            let averageConfidence = candidates.isEmpty
                ? nil
                : Double(candidates.map(\.confidence).reduce(0, +) / Float(candidates.count))

            ocrLogger.info("vision request completed observations=\(observations.count, privacy: .public) lines=\(lines.count, privacy: .public)")
            return RecognizedTextPayload(lines: lines, averageConfidence: averageConfidence)
        }.value
    }
}

private struct RecognizedTextPayload {
    var lines: [String]
    var averageConfidence: Double?
}

private enum OCRResult {
    case recognized(RecognizedTextPayload)
    case timedOut
}

private func elapsedMilliseconds(since date: Date) -> Int {
    Int(Date().timeIntervalSince(date) * 1000)
}

private extension UIImage {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:
            return .up
        case .down:
            return .down
        case .left:
            return .left
        case .right:
            return .right
        case .upMirrored:
            return .upMirrored
        case .downMirrored:
            return .downMirrored
        case .leftMirrored:
            return .leftMirrored
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}
