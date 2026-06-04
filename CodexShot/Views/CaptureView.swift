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
                .padding(.top, 8)
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
            GlassEffectContainer(spacing: 20) {
                contentStack
            }
        } else {
            contentStack
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusCapsule
            screenshotPanel
            sendButton
            contextComposer

            if !statusText.isEmpty {
                Label(statusText, systemImage: "sparkle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.brandDeep)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: statusText)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("CodexShot")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("Capture · annotate · relay")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GlassIconButton(systemName: "arrow.triangle.2.circlepath", tint: Theme.brand, size: 42) {
                store.reload()
            }
            .accessibilityLabel("Reload")
        }
        .padding(.top, 2)
    }

    private var statusCapsule: some View {
        GlassPanel(
            tint: store.hasEndpoint ? Theme.brand.opacity(0.10) : Theme.warning.opacity(0.14),
            cornerRadius: 24,
            padding: 11
        ) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill((store.hasEndpoint ? Theme.brand : Theme.warning).opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: store.hasEndpoint ? "point.3.connected.trianglepath.dotted" : "link.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(store.hasEndpoint ? Theme.brand : Theme.warning)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.hasEndpoint ? "Relay ready" : "Relay needed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(store.hasEndpoint ? Theme.brandDeep : .primary)
                    Text(store.hasEndpoint ? endpointDisplay : "Add a relay endpoint in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                StatusDot(color: store.hasEndpoint ? .green : Theme.warning)
            }
        }
    }

    private var screenshotPanel: some View {
        GlassPanel(tint: Theme.brandBright.opacity(0.12), interactive: true, cornerRadius: Theme.Radius.card, padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Label("Screenshot", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(imageData == nil ? "Choose" : "Replace", systemImage: imageData == nil ? "plus" : "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .foregroundStyle(Theme.brandDeep)
                            .background(Theme.brand.opacity(0.14), in: Capsule())
                            .overlay { Capsule().strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 2)

                previewWell
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)

                chipRow
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
    }

    private var previewWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.65),
                            Theme.brandBright.opacity(0.20),
                            Color.mint.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.65), lineWidth: 1)
                }

            previewImage
        }
        .frame(height: 272)
    }

    @ViewBuilder
    private var previewImage: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 168, maxHeight: 238)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 14)
        } else {
            DeviceMockup()
        }
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            CaptureChip(symbol: "viewfinder", title: "OCR ready", tint: Theme.brand)
            CaptureChip(
                symbol: "text.bubble",
                title: store.settings.threadHint.isEmpty ? "Thread hint" : "Thread set",
                tint: Theme.accentBlue
            )
            CaptureChip(
                symbol: store.hasEndpoint ? "lock.shield" : "link.badge.plus",
                title: store.hasEndpoint ? "Private relay" : "Endpoint",
                tint: store.hasEndpoint ? Theme.brandBright : Theme.warning
            )
        }
    }

    private var sendButton: some View {
        HeroSendButton(isBusy: isSending) {
            Task { await sendSelectedImage() }
        } label: {
            HStack(spacing: 10) {
                if isSending {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(isSending ? "Sending…" : "Send to Codex")
                    .font(.headline.weight(.semibold))
            }
        }
        .disabled(isSending)
    }

    private var contextComposer: some View {
        GlassPanel(tint: .white.opacity(0.18), interactive: true, cornerRadius: 26, padding: 10) {
            HStack(alignment: .center, spacing: 10) {
                TextField("What should Codex focus on?", text: $note, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.leading, 6)

                GlassIconButton(systemName: "wand.and.sparkles", tint: Theme.brand, size: 42) {
                    if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        note = store.settings.defaultContext
                    }
                }
                .accessibilityLabel("Use default context")
            }
            .frame(minHeight: 42)
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
        statusText = "Preparing capture…"
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

private struct StatusDot: View {
    var color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 18, height: 18)
                .scaleEffect(pulse ? 1.0 : 0.6)
                .opacity(pulse ? 0 : 0.8)
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.6), radius: 5)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
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
            .minimumScaleFactor(0.72)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1)
            }
    }
}

#Preview {
    NavigationStack {
        CaptureView(store: CaptureStore())
    }
}
