import SwiftUI

extension CaptureStatus {
    var symbolName: String {
        switch self {
        case .needsEndpoint:
            "link.badge.plus"
        case .sending:
            "arrow.up.circle"
        case .sent:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .needsEndpoint:
            .orange
        case .sending:
            .blue
        case .sent:
            .green
        case .failed:
            .red
        }
    }
}

