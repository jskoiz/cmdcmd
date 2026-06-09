import SwiftUI
import UIKit

struct ShareCaptureView: View {
    var loadInput: () async -> SharedCaptureInput
    var finish: () -> Void
    var openSettings: (@escaping (Bool) -> Void) -> Void = { completion in
        completion(false)
    }

    @State private var input = SharedCaptureInput()
    @State private var phase: ShareSendPhase = .loading
    @State private var didStart = false
    @State private var isShowingFailureHelp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: phase.canRetry ? 14 : 10) {
                statusPanel
                actionPanel
            }
            .animation(.spring(response: 0.44, dampingFraction: 0.86), value: phase.canClose)
            .padding(.horizontal, 22)
            .padding(.vertical, phase.canRetry ? 18 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background {
                AppBackground()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await loadAndSendOnce()
            }
            .alert("Fix Relay Connection", isPresented: $isShowingFailureHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failureHelpMessage)
            }
        }
    }

    private var statusPanel: some View {
        AppshotCaptureFeedbackView(
            phase: phase.feedbackPhase,
            imageData: input.imageData,
            message: phase.feedbackMessage,
            openSettings: openSettingsForCurrentFailure,
            settingsActionTitle: CaptureFailurePresentation.settingsActionTitle(for: phase.feedbackMessage)
        )
    }

    @ViewBuilder
    private var actionPanel: some View {
        if phase.canClose {
            HStack(spacing: 12) {
                ShareActionButton(title: phase.closeActionTitle, style: phase.closeActionStyle, action: finish)

                if phase.canRetry {
                    ShareActionButton(title: "Try Again", style: .primary) {
                        Task { await send(input) }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func loadAndSendOnce() async {
        guard !didStart else {
            return
        }

        didStart = true
        phase = .loading
        input = await loadInput()
        await send(input)
    }

    private func send(_ input: SharedCaptureInput) async {
        guard let data = input.imageData else {
            phase = .failed("No image was shared.")
            AppshotFeedback.shared.playCompletion(success: false)
            return
        }

        phase = .loading
        AppshotFeedback.shared.playCaptureStart()

        #if targetEnvironment(simulator)
        await simulateSimulatorSend()
        #else
        let settings = CaptureRepository.loadSettings()
        let readiness = await RelayClient(settings: settings).checkReadiness()
        if let failureMessage = readiness.failureMessage {
            phase = .failed(failureMessage)
            AppshotFeedback.shared.playCompletion(success: false)
            return
        }

        phase = .sending
        let record = await CapturePipeline.submit(
            imageData: data,
            filename: input.filename.isEmpty ? "shared-screenshot.png" : input.filename,
            note: input.sourceText,
            source: .shareExtension,
            sourceDetail: "Share Sheet"
        )

        if record.status == .sent {
            phase = .sent(record.statusMessage)
            AppshotFeedback.shared.playCompletion(success: true)
        } else {
            phase = .failed(record.statusMessage)
            AppshotFeedback.shared.playCompletion(success: false)
        }
        #endif
    }

    #if targetEnvironment(simulator)
    private func simulateSimulatorSend() async {
        phase = .sending
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        phase = .sent("Simulated send complete.")
        AppshotFeedback.shared.playCompletion(success: true)
    }
    #endif

    private func openSettingsForCurrentFailure() {
        switch CaptureFailurePresentation.settingsDestination(for: phase.feedbackMessage) {
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
        if let message = phase.feedbackMessage, !message.isEmpty {
            return "\(message)\n\nIf iOS shows a Local Network toggle for cmd+cmd, turn it on. If that toggle is missing, open cmd+cmd relay settings and confirm the endpoint matches the Mac relay URL."
        }

        return "Open cmd+cmd relay settings and confirm the endpoint matches the Mac relay URL."
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

private enum ShareSendPhase: Equatable {
    case loading
    case sending
    case sent(String)
    case failed(String)

    var feedbackPhase: AppshotSendFeedbackPhase {
        switch self {
        case .loading:
            .preparing
        case .sending:
            .sending
        case .sent:
            .sent
        case .failed:
            .failed
        }
    }

    var feedbackMessage: String? {
        switch self {
        case .loading, .sending, .sent:
            nil
        case .failed(let message):
            message
        }
    }

    var canRetry: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    var canClose: Bool {
        switch self {
        case .sent, .failed:
            true
        case .loading, .sending:
            false
        }
    }

    var closeActionTitle: String {
        switch self {
        case .sent:
            "Continue"
        case .loading, .sending, .failed:
            "Close"
        }
    }

    var closeActionStyle: ShareActionButton.Style {
        switch self {
        case .sent:
            .primary
        case .loading, .sending, .failed:
            .secondary
        }
    }
}
