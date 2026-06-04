import Foundation
import OSLog
import UIKit
import Vision

private let ocrLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.jskoiz.CodexShot",
    category: "OCRService"
)

enum OCRService {
    static func recognizedText(from imageData: Data) async -> String {
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

            let result = await group.next() ?? .recognized("")
            group.cancelAll()
            switch result {
            case .recognized(let text):
                ocrLogger.info(
                    "recognition task group completed textChars=\(text.count, privacy: .public) durationMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
                )
                return text
            case .timedOut:
                ocrLogger.error(
                    "recognition timed out durationMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
                )
                return ""
            }
        }
    }

    private static func performRecognition(from imageData: Data) async -> String {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
                ocrLogger.error("recognition failed to decode image")
                return ""
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
                return ""
            }

            let observations = request.results ?? []
            let lines = observations
                .sorted { lhs, rhs in
                    if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                .compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

            ocrLogger.info("vision request completed observations=\(observations.count, privacy: .public) lines=\(lines.count, privacy: .public)")
            return lines.joined(separator: "\n")
        }.value
    }
}

private enum OCRResult {
    case recognized(String)
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
