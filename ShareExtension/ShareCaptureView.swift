import SwiftUI

struct ShareCaptureView: View {
    private let finish: () -> Void
    private let openSettings: (@escaping (Bool) -> Void) -> Void

    @State private var coordinator: ShareBatchCoordinator
    @State private var isShowingFailureHelp = false

    init(
        loadInput: @escaping ShareBatchCoordinator.InputLoader,
        finish: @escaping () -> Void,
        openSettings: @escaping (@escaping (Bool) -> Void) -> Void = { completion in
            completion(false)
        }
    ) {
        self.finish = finish
        self.openSettings = openSettings
        _coordinator = State(initialValue: ShareBatchCoordinator(
            loadInput: loadInput,
            submit: { image, sourceText, index, total in
                try await CapturePipeline.submit(
                    imageData: image.data,
                    filename: Self.filename(for: image, index: index, total: total),
                    note: sourceText,
                    source: .shareExtension,
                    sourceDetail: Self.sourceDetail(index: index, total: total)
                )
            },
            endpointFailure: ShareBatchCoordinator.currentEndpointFailure,
            finish: finish
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: coordinator.phase.canRetry ? 14 : 10) {
                CaptureFeedbackView(
                    phase: coordinator.phase.feedbackPhase,
                    imageData: coordinator.input.previewImageData,
                    imageCount: coordinator.input.images.count,
                    message: coordinator.phase.feedbackMessage,
                    openSettings: coordinator.phase.canOpenSettings ? openSettingsForCurrentFailure : nil,
                    settingsActionTitle: CaptureFailurePresentation.settingsActionTitle(
                        for: coordinator.phase.feedbackMessage
                    )
                )

                ShareActionPanel(
                    phase: coordinator.phase,
                    close: finish,
                    retry: coordinator.retry
                )
            }
            .animation(.spring(response: 0.44, dampingFraction: 0.86), value: coordinator.phase.canClose)
            .padding(.horizontal, 22)
            .padding(.vertical, coordinator.phase.canRetry ? 18 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background { AppBackground() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                coordinator.start()
                await coordinator.waitUntilIdle()
            }
            .onDisappear {
                coordinator.cancel()
            }
            .onChange(of: coordinator.phase) { oldPhase, newPhase in
                playFeedback(from: oldPhase, to: newPhase)
            }
            .alert("Fix Relay Connection", isPresented: $isShowingFailureHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failureHelpMessage)
            }
        }
    }

    private func playFeedback(from oldPhase: ShareBatchPhase, to newPhase: ShareBatchPhase) {
        if newPhase.isSending, !oldPhase.isSending {
            CaptureFeedback.shared.playCaptureStart()
        }

        switch newPhase {
        case .sent:
            CaptureFeedback.shared.playCompletion(success: true)
        case .pending, .failed:
            CaptureFeedback.shared.playCompletion(success: false)
        case .loading, .sending:
            break
        }
    }

    private func openSettingsForCurrentFailure() {
        switch CaptureFailurePresentation.settingsDestination(for: coordinator.phase.feedbackMessage) {
        case .relay:
            openSettings { didOpen in
                Task { @MainActor in
                    if !didOpen {
                        isShowingFailureHelp = true
                    }
                }
            }
        case .systemApp:
            isShowingFailureHelp = true
        }
    }

    private var failureHelpMessage: String {
        if let message = coordinator.phase.feedbackMessage, !message.isEmpty {
            return "\(message)\n\nIf iOS shows a Local Network toggle for cmd+cmd, turn it on. If that toggle is missing, open cmd+cmd relay settings and confirm the endpoint matches the Mac relay URL."
        }
        return "Open cmd+cmd relay settings and confirm the endpoint matches the Mac relay URL."
    }

    private static func filename(for image: SharedCaptureImage, index: Int, total: Int) -> String {
        let filename = image.filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filename.isEmpty {
            return filename
        }
        return total > 1 ? "shared-screenshot-\(index + 1).png" : "shared-screenshot.png"
    }

    private static func sourceDetail(index: Int, total: Int) -> String {
        total > 1 ? "Share Sheet \(index + 1) of \(total)" : "Share Sheet"
    }
}

private struct ShareActionPanel: View {
    var phase: ShareBatchPhase
    var close: () -> Void
    var retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ShareActionButton(
                title: phase.closeActionTitle,
                style: phase.closeActionStyle,
                action: close
            )

            if phase.canRetry {
                ShareActionButton(title: "Try Again", style: .primary, action: retry)
            }
        }
        .opacity(phase.canClose ? 1 : 0)
        .allowsHitTesting(phase.canClose)
        .accessibilityHidden(!phase.canClose)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct ShareActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    var title: String
    var style: Style
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(style == .primary ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    Capsule()
                        .fill(backgroundStyle)
                        .overlay {
                            Capsule()
                                .strokeBorder(.white.opacity(style == .primary ? 0.16 : 0.58), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .shadow(
            color: style == .primary ? .black.opacity(0.18) : .black.opacity(0.06),
            radius: style == .primary ? 14 : 8,
            x: 0,
            y: style == .primary ? 8 : 4
        )
    }

    private var backgroundStyle: AnyShapeStyle {
        switch style {
        case .primary:
            AnyShapeStyle(Color.black)
        case .secondary:
            AnyShapeStyle(.regularMaterial)
        }
    }
}

private extension ShareBatchPhase {
    var feedbackPhase: CaptureSendFeedbackPhase {
        switch self {
        case .loading:
            .preparing
        case .sending:
            .sending
        case .sent:
            .sent
        case .pending:
            .pending
        case .failed:
            .failed
        }
    }

    var canOpenSettings: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    var isSending: Bool {
        if case .sending = self {
            return true
        }
        return false
    }

    var closeActionTitle: String {
        if case .sent = self {
            return "Continue"
        }
        return "Close"
    }

    var closeActionStyle: ShareActionButton.Style {
        if case .sent = self {
            return .primary
        }
        return .secondary
    }
}
