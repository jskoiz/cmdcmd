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
                    candidate.confidence >= 0.40
                }
                .map { candidate in
                    RecognizedLine(text: candidate.string, confidence: candidate.confidence)
                }
            let cleanedLines = OCRTextCleaner.cleanedLines(from: candidates)
            let lines = cleanedLines.map(\.text)
            let averageConfidence = cleanedLines.isEmpty
                ? nil
                : Double(cleanedLines.map(\.confidence).reduce(0, +) / Float(cleanedLines.count))

            ocrLogger.info("vision request completed observations=\(observations.count, privacy: .public) rawLines=\(candidates.count, privacy: .public) cleanedLines=\(lines.count, privacy: .public)")
            return RecognizedTextPayload(lines: lines, averageConfidence: averageConfidence)
        }.value
    }
}

private struct RecognizedLine {
    var text: String
    var confidence: Float
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

private enum OCRTextCleaner {
    private static let maxLines = 16
    private static let maxCharacters = 1_200
    private static let ignoredStatusLines: Set<String> = [
        "phone"
    ]
    private static let allowedTrailingCharacters = Set(".!?%")

    static func cleanedLines(from recognizedLines: [RecognizedLine]) -> [RecognizedLine] {
        var cleanedLines: [RecognizedLine] = []
        var seenKeys = Set<String>()
        var characterCount = 0

        for recognizedLine in recognizedLines {
            guard let text = cleanedText(recognizedLine.text),
                  isInformative(text) else {
                continue
            }

            let key = dedupeKey(text)
            guard !key.isEmpty, !seenKeys.contains(key) else {
                continue
            }

            let nextCharacterCount = characterCount + text.count + (cleanedLines.isEmpty ? 0 : 1)
            guard cleanedLines.isEmpty || nextCharacterCount <= maxCharacters else {
                break
            }

            cleanedLines.append(RecognizedLine(text: text, confidence: recognizedLine.confidence))
            seenKeys.insert(key)
            characterCount = nextCharacterCount

            if cleanedLines.count >= maxLines {
                break
            }
        }

        return cleanedLines
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
