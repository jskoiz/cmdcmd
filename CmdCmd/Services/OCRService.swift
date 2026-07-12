import Foundation
import OSLog
import UIKit
import Vision

private let ocrLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.jskoiz.CmdCmd",
    category: "OCRService"
)

enum OCRService {
    typealias Recognizer = @Sendable (Data, OCRCancellationController) async throws -> OCRRecognitionResult

    static func report(from imageData: Data) async throws -> OCRReport {
        try await report(
            from: imageData,
            timeoutNanoseconds: 4_000_000_000,
            recognizer: { imageData, cancellation in
                try await recognizeWithVision(
                    imageData: imageData,
                    cancellation: cancellation
                )
            }
        )
    }

    static func report(
        from imageData: Data,
        timeoutNanoseconds: UInt64,
        recognizer: @escaping Recognizer
    ) async throws -> OCRReport {
        let startedAt = Date()
        ocrLogger.info("recognition task group started imageBytes=\(imageData.count, privacy: .public)")
        let cancellation = OCRCancellationController()

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: OCRRaceResult.self) { group in
                group.addTask {
                    do {
                        return .recognized(try await recognizer(imageData, cancellation))
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        ocrLogger.error("recognition worker failed error=\(error.localizedDescription, privacy: .public)")
                        return .recognized(.empty)
                    }
                }

                group.addTask {
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                        return .timedOut
                    } catch {
                        return .cancelled
                    }
                }

                guard let firstResult = try await group.next() else {
                    group.cancelAll()
                    return makeReport(from: .empty, startedAt: startedAt, timedOut: false)
                }

                switch firstResult {
                case .recognized(let result):
                    group.cancelAll()
                    while try await group.next() != nil {}
                    try Task.checkCancellation()
                    return makeReport(from: result, startedAt: startedAt, timedOut: false)
                case .timedOut:
                    cancellation.cancel()
                    group.cancelAll()
                    while try await group.next() != nil {}
                    try Task.checkCancellation()
                    let durationMs = elapsedMilliseconds(since: startedAt)
                    ocrLogger.error("recognition timed out durationMs=\(durationMs, privacy: .public)")
                    return makeReport(from: .empty, startedAt: startedAt, timedOut: true)
                case .cancelled:
                    cancellation.cancel()
                    group.cancelAll()
                    while try await group.next() != nil {}
                    throw CancellationError()
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func recognizeWithVision(
        imageData: Data,
        cancellation: OCRCancellationController
    ) async throws -> OCRRecognitionResult {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
                ocrLogger.error("recognition failed to decode image")
                return .empty
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.012
            cancellation.install {
                request.cancel()
            }
            defer { cancellation.removeHandler() }
            try cancellation.checkCancellation()

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImageOrientation)

            do {
                try handler.perform([request])
            } catch {
                if cancellation.isCancelled || Task.isCancelled {
                    throw CancellationError()
                }
                ocrLogger.error("vision request failed error=\(error.localizedDescription, privacy: .public)")
                return .empty
            }
            try cancellation.checkCancellation()

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
            return OCRRecognitionResult(lines: lines, averageConfidence: averageConfidence)
        }.value
    }

    private static func makeReport(
        from result: OCRRecognitionResult,
        startedAt: Date,
        timedOut: Bool
    ) -> OCRReport {
        let durationMs = elapsedMilliseconds(since: startedAt)
        let text = result.lines.joined(separator: "\n")
        ocrLogger.info(
            "recognition completed textChars=\(text.count, privacy: .public) lines=\(result.lines.count, privacy: .public) durationMs=\(durationMs, privacy: .public) timedOut=\(timedOut, privacy: .public)"
        )
        return OCRReport(
            text: text,
            durationMs: durationMs,
            lineCount: result.lines.count,
            characterCount: text.count,
            timedOut: timedOut,
            averageConfidence: result.averageConfidence
        )
    }
}

private struct RecognizedLine {
    var text: String
    var confidence: Float
}

struct OCRRecognitionResult: Sendable {
    var lines: [String]
    var averageConfidence: Double?

    static let empty = OCRRecognitionResult(lines: [], averageConfidence: nil)
}

private enum OCRRaceResult: Sendable {
    case recognized(OCRRecognitionResult)
    case timedOut
    case cancelled
}

final class OCRCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func install(_ handler: @escaping @Sendable () -> Void) {
        let shouldCancel = lock.withLock { () -> Bool in
            if cancelled {
                return true
            }
            self.handler = handler
            return false
        }
        if shouldCancel {
            handler()
        }
    }

    func removeHandler() {
        lock.withLock {
            handler = nil
        }
    }

    func cancel() {
        let handler = lock.withLock { () -> (@Sendable () -> Void)? in
            guard !cancelled else {
                return nil
            }
            cancelled = true
            return self.handler
        }
        handler?()
    }

    func checkCancellation() throws {
        if isCancelled || Task.isCancelled {
            throw CancellationError()
        }
    }
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
