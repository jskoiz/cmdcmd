import Foundation

enum Formatters {
    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

/// Whole milliseconds elapsed since `date`, for timing diagnostics.
func elapsedMilliseconds(since date: Date) -> Int {
    Int(Date().timeIntervalSince(date) * 1000)
}

/// Last six characters of a token, for non-sensitive log redaction.
func tokenSuffix(_ token: String) -> String {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return "none"
    }
    return String(trimmed.suffix(6))
}

