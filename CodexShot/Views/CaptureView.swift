import PhotosUI
import SwiftUI
import UIKit

struct CaptureView: View {
    @Bindable var store: CaptureStore
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var note = ""
    @State private var isSending = false
    @State private var statusText = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            glassStack
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 32)
        }
        .background {
            AppBackground()
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                imageData = try? await newValue.loadTransferable(type: Data.self)
            }
        }
    }

    @ViewBuilder
    private var glassStack: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                contentStack
            }
        } else {
            contentStack
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusCapsule
            screenshotPanel
            sendButton
            contextComposer

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("CodexShot")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            GlassIconButton(systemName: "arrow.triangle.2.circlepath", tint: .teal) {
                store.reload()
            }
            .accessibilityLabel("Reload")
        }
        .padding(.top, 8)
    }

    private var statusCapsule: some View {
        GlassPanel(
            tint: store.hasEndpoint ? .teal.opacity(0.12) : .orange.opacity(0.14),
            cornerRadius: 34,
            padding: 12
        ) {
            HStack(spacing: 12) {
                Image(systemName: store.hasEndpoint ? "point.3.connected.trianglepath.dotted" : "link.badge.plus")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(store.hasEndpoint ? .teal : .orange)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.hasEndpoint ? "Relay ready" : "Relay needed")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(store.hasEndpoint ? .teal : .primary)
                    Text(store.hasEndpoint ? endpointDisplay : "add relay endpoint")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                Circle()
                    .fill(store.hasEndpoint ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)
                    .shadow(color: (store.hasEndpoint ? Color.green : Color.orange).opacity(0.4), radius: 8)
            }
        }
    }

    private var screenshotPanel: some View {
        GlassPanel(tint: .cyan.opacity(0.13), interactive: true, cornerRadius: 34, padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Label("Screenshot", systemImage: "photo")
                        .font(.headline.weight(.semibold))

                    Spacer()

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(imageData == nil ? "Choose" : "Replace", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.teal.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.teal)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 8)

                previewWell
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
    }

    private var previewWell: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.70),
                            Color.cyan.opacity(0.18),
                            Color.mint.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: .teal.opacity(0.10), radius: 26, x: 0, y: 18)

            previewImage

            HStack(spacing: 8) {
                CaptureChip(symbol: "viewfinder", title: "OCR ready", tint: .teal)
                CaptureChip(symbol: "text.bubble", title: store.settings.threadHint.isEmpty ? "Thread hint" : "Thread set", tint: .blue)
                CaptureChip(symbol: store.hasEndpoint ? "lock.shield" : "link.badge.plus", title: store.hasEndpoint ? "Private relay" : "Endpoint", tint: store.hasEndpoint ? .cyan : .orange)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(height: 216)
    }

    @ViewBuilder
    private var previewImage: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 168, maxHeight: 166)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 14)
                .padding(.bottom, 42)
        } else {
            MockScreenshotCard()
                .padding(.bottom, 42)
        }
    }

    private var sendButton: some View {
        PrimaryGlassButton {
            Task { await sendSelectedImage() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "paperplane")
                    .font(.system(size: 26, weight: .semibold))
                Text(isSending ? "Sending" : "Send to Codex")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .tint(.teal)
        .disabled(isSending)
    }

    private var contextComposer: some View {
        GlassPanel(tint: .white.opacity(0.16), interactive: true, cornerRadius: 32, padding: 14) {
            HStack(alignment: .center, spacing: 12) {
                TextField("What should Codex focus on?", text: $note, axis: .vertical)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .padding(.leading, 4)

                GlassIconButton(systemName: "wand.and.sparkles", tint: .teal, size: 52) {
                    if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        note = store.settings.defaultContext
                    }
                }
                .accessibilityLabel("Use default context")
            }
            .frame(minHeight: 52)
        }
    }

    private var endpointDisplay: String {
        if let host = URL(string: store.settings.endpoint)?.host(), !host.isEmpty {
            return "\(host) · local"
        }
        return store.settings.endpoint
    }

    private func sendSelectedImage() async {
        guard let imageData else {
            statusText = "Choose a screenshot first"
            return
        }
        isSending = true
        statusText = "Preparing capture"
        let record = await store.submit(
            imageData: imageData,
            filename: "screenshot.png",
            note: note,
            source: .mainApp
        )
        statusText = record.statusMessage
        isSending = false
    }
}

private struct CaptureChip: View {
    var symbol: String
    var title: String
    var tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.58), lineWidth: 1)
            }
    }
}

private struct MockScreenshotCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 7, height: 7)
                Text("CaptureContext.swift")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.80))
                Spacer()
                Image(systemName: "wifi")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 7) {
                CodeLine(width: 112, color: .pink)
                CodeLine(width: 154, color: .cyan)
                CodeLine(width: 126, color: .mint)
                CodeLine(width: 168, color: .white.opacity(0.55))
                CodeLine(width: 138, color: .orange.opacity(0.85))
                CodeLine(width: 96, color: .white.opacity(0.45))
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                LogLine(text: "[CodexShot] OCR extracted 128 lines")
                LogLine(text: "[CodexShot] Relay delivered")
            }
        }
        .padding(14)
            .frame(width: 150, height: 158)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.11), Color(red: 0.02, green: 0.04, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 20, x: 0, y: 14)
    }
}

private struct CodeLine: View {
    var width: CGFloat
    var color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: 4)
    }
}

private struct LogLine: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.green.opacity(0.88))
            .lineLimit(1)
    }
}

#Preview {
    NavigationStack {
        CaptureView(store: CaptureStore())
    }
}
