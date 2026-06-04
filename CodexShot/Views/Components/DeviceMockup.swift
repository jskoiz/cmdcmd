import SwiftUI

/// A miniature, realistic phone showing a Swift file under review with a live
/// CodexShot relay log. This is the hero illustration on the Capture screen.
struct DeviceMockup: View {
    var body: some View {
        VStack(spacing: 0) {
            statusBar
            fileTab
            Divider().overlay(Color.white.opacity(0.08))
            codeBody
            relayLog
        }
        .frame(width: 158, height: 256)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.11, blue: 0.13),
                    Color(red: 0.03, green: 0.05, blue: 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
        }
        .overlay(alignment: .top) {
            // Dynamic Island pill
            Capsule()
                .fill(.black)
                .frame(width: 42, height: 12)
                .padding(.top, 6)
        }
        .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 16)
        .shadow(color: Theme.brand.opacity(0.16), radius: 14, x: 0, y: 6)
    }

    private var statusBar: some View {
        HStack {
            Text("9:41")
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
            Spacer()
            HStack(spacing: 2.5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
            }
            .font(.system(size: 6.5, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 13)
        .padding(.top, 7)
        .padding(.bottom, 6)
    }

    private var fileTab: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left")
                .foregroundStyle(.white.opacity(0.5))
            Image(systemName: "swift")
                .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.30))
            Text("NetworkingService.swift")
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 2.5) {
                Image(systemName: "arrow.triangle.branch")
                Text("main")
            }
            .foregroundStyle(.white.opacity(0.45))
        }
        .font(.system(size: 6.5, weight: .medium))
        .padding(.horizontal, 11)
        .padding(.bottom, 6)
    }

    private var codeBody: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            ForEach(Array(Self.code.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1)")
                        .foregroundStyle(.white.opacity(0.22))
                        .frame(width: 8, alignment: .trailing)
                    line.rendered
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 6.3, weight: .medium, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.top, 3)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var relayLog: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            logLine("Upload complete · 1.2 MB")
            logLine("OCR extracted 128 lines")
            logLine("Relay delivered", done: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.35))
    }

    private func logLine(_ text: String, done: Bool = false) -> some View {
        HStack(spacing: 3.5) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 5.5, weight: .bold))
            Text("[CodexShot] ") .foregroundStyle(.white.opacity(0.45))
                + Text(text).foregroundStyle(Color(red: 0.40, green: 0.90, blue: 0.55))
        }
        .font(.system(size: 5.8, weight: .medium, design: .monospaced))
        .foregroundStyle(Color(red: 0.40, green: 0.90, blue: 0.55))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: Syntax-highlighted source lines

    private static let code: [CodeLine] = [
        CodeLine([.kw("struct"), .ty(" NetworkingService"), .p(" {")]),
        CodeLine([.kw("  func"), .fn(" send"), .p("(_ request: "), .ty("URLRequest"), .p(")")]),
        CodeLine([.kw("    async throws"), .p(" -> ("), .ty("Data"), .p(", "), .ty("URLResponse"), .p(") {")]),
        CodeLine([.kw("    let"), .p(" (data, response) = "), .kw("try await")]),
        CodeLine([.ty("      URLSession"), .p(".shared.data(for: request)")]),
        CodeLine([.kw("    guard let"), .p(" http = response "), .kw("as?")]),
        CodeLine([.ty("    HTTPURLResponse"), .kw(" else"), .p(" {")]),
        CodeLine([.kw("      throw"), .ty(" NetworkError"), .p(".invalidResponse")]),
        CodeLine([.p("    }")]),
        CodeLine([.kw("    return"), .p(" (data, response)")]),
        CodeLine([.p("  }")]),
        CodeLine([.p("}")])
    ]
}

/// A single line of fake source built from coloured tokens.
private struct CodeLine {
    let tokens: [Token]
    init(_ tokens: [Token]) { self.tokens = tokens }

    enum Token {
        case kw(String)   // keyword
        case ty(String)   // type
        case fn(String)   // function name
        case p(String)    // plain / punctuation

        var color: Color {
            switch self {
            case .kw: Color(red: 0.98, green: 0.46, blue: 0.66)
            case .ty: Color(red: 0.42, green: 0.86, blue: 0.86)
            case .fn: Color(red: 0.49, green: 0.66, blue: 0.99)
            case .p: Color.white.opacity(0.78)
            }
        }

        var text: String {
            switch self {
            case let .kw(s), let .ty(s), let .fn(s), let .p(s): s
            }
        }
    }

    var rendered: Text {
        tokens.reduce(Text("")) { partial, token in
            partial + Text(token.text).foregroundColor(token.color)
        }
    }
}

#Preview {
    DeviceMockup()
        .padding(40)
        .background(Color.gray.opacity(0.2))
}
