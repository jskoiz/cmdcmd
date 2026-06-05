import OSLog
import PhotosUI
import SwiftUI
import UIKit

private let captureViewLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.jskoiz.CodexShot",
    category: "CaptureView"
)

struct CaptureView: View {
    @Bindable var store: CaptureStore
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isSending = false
    @State private var statusText = ""
    @State private var feedbackPhase: AppshotSendFeedbackPhase?
    @State private var feedbackMessage: String?
    @State private var feedbackToken = UUID()

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                glassStack(height: max(proxy.size.height - 32, 0))
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
            }

            feedbackOverlay
        }
        .background {
            AppBackground()
        }
        .safeAreaInset(edge: .bottom) {
            sendButton
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 8)
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
    private func glassStack(height: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                contentStack(height: height)
            }
        } else {
            contentStack(height: height)
        }
    }

    private func contentStack(height: CGFloat) -> some View {
        let panelHeight = min(max(height - 190, 430), 560)

        return VStack(alignment: .leading, spacing: 16) {
            header
            screenshotPanel(height: panelHeight)

            if feedbackPhase == nil, !statusText.isEmpty {
                Label(statusText, systemImage: "sparkle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, -2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: statusText)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                Image(systemName: "command")
                Text("+")
                Image(systemName: "command")
            }
            .font(.system(size: 29, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .accessibilityLabel("cmd plus cmd")

            Spacer()
        }
    }

    private func screenshotPanel(height: CGFloat) -> some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            previewWell(height: height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(imageData == nil ? "Choose image" : "Replace image")
        .frame(height: height)
    }

    private func previewWell(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemBackground).opacity(0.82),
                            Color(.systemBackground).opacity(0.72),
                            Color(.systemGray5).opacity(0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.brand.opacity(0.08), lineWidth: 1)
                }

            previewImage
        }
        .frame(height: height)
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
                        .strokeBorder(.white.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 12)
        } else {
            ImagePlaceholder()
        }
    }

    private var sendButton: some View {
        let showsInlineProgress = isSending && feedbackPhase == nil

        return HeroSendButton(isBusy: isSending) {
            Task { await sendSelectedImage() }
        } label: {
            HStack(spacing: 10) {
                if showsInlineProgress {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else if !isSending {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(isSending ? "Sending…" : "⌘+⌘")
                    .font(.headline.weight(.semibold))
            }
        }
        .disabled(isSending)
    }

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let feedbackPhase {
            Color.black.opacity(0.08)
                .ignoresSafeArea()
                .transition(.opacity)

            AppshotCaptureFeedbackView(
                phase: feedbackPhase,
                imageData: imageData,
                message: feedbackMessage
            )
            .id(feedbackToken)
            .transition(.opacity)
            .padding(.horizontal, 22)
        }
    }

    @MainActor
    private func sendSelectedImage() async {
        guard let imageData else {
            statusText = "Choose a screenshot first"
            AppshotFeedback.shared.playCompletion(success: false)
            captureViewLogger.info("send requested without selected image")
            return
        }
        captureViewLogger.info(
            "send requested imageBytes=\(imageData.count, privacy: .public)"
        )
        let token = UUID()
        feedbackToken = token
        isSending = true
        statusText = ""
        feedbackMessage = nil
        feedbackPhase = .sending
        AppshotFeedback.shared.playCaptureStart()
        captureViewLogger.info("ui status set preparing capture")
        let record = await store.submit(
            imageData: imageData,
            filename: "screenshot.png",
            note: "",
            source: .mainApp
        )
        let didSend = record.status == .sent
        statusText = record.statusMessage
        feedbackMessage = didSend ? nil : record.statusMessage
        feedbackPhase = didSend ? .sent : .failed
        AppshotFeedback.shared.playCompletion(success: didSend)
        isSending = false
        captureViewLogger.info(
            "send completed status=\(record.status.rawValue, privacy: .public) message=\(record.statusMessage, privacy: .public)"
        )
        await hideFeedback(after: didSend ? 850_000_000 : 1_800_000_000, token: token)
    }

    @MainActor
    private func hideFeedback(after nanoseconds: UInt64, token: UUID) async {
        try? await Task.sleep(nanoseconds: nanoseconds)
        guard feedbackToken == token else {
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            feedbackPhase = nil
            feedbackMessage = nil
        }
    }
}

#Preview {
    NavigationStack {
        CaptureView(store: CaptureStore())
    }
}
