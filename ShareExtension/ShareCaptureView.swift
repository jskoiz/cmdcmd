import SwiftUI
import UIKit

struct ShareCaptureView: View {
    var loadInput: () async -> SharedCaptureInput
    var finish: () -> Void

    @State private var input = SharedCaptureInput()
    @State private var phase: ShareSendPhase = .loading
    @State private var didStart = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Spacer(minLength: 10)
                statusPanel
                actionPanel
                Spacer(minLength: 10)
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                AppBackground()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await loadAndSendOnce()
            }
        }
    }

    private var statusPanel: some View {
        AppshotCaptureFeedbackView(
            phase: phase.feedbackPhase,
            imageData: input.imageData,
            message: phase.feedbackMessage
        )
    }

    @ViewBuilder
    private var actionPanel: some View {
        if phase.canRetry {
            HStack(spacing: 12) {
                ShareActionButton(title: "Close", style: .secondary, action: finish)
                ShareActionButton(title: "Try Again", style: .primary) {
                    Task { await send(input) }
                }
            }
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

        phase = .sending
        AppshotFeedback.shared.playCaptureStart()
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
            try? await Task.sleep(nanoseconds: 650_000_000)
            finish()
        } else {
            phase = .failed(record.statusMessage)
            AppshotFeedback.shared.playCompletion(success: false)
        }
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

    var isWorking: Bool {
        switch self {
        case .loading, .sending:
            true
        case .sent, .failed:
            false
        }
    }

    var canRetry: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}
