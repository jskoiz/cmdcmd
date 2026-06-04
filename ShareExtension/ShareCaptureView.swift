import SwiftUI
import UIKit

struct ShareCaptureView: View {
    var loadInput: () async -> SharedCaptureInput
    var finish: () -> Void
    var cancel: () -> Void

    @State private var input = SharedCaptureInput()
    @State private var phase: ShareSendPhase = .loading
    @State private var didStart = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                preview
                statusPanel
                actionPanel
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                AppBackground()
            }
            .navigationTitle("CodexShot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                        .disabled(phase.isWorking)
                }
            }
            .task {
                await loadAndSendOnce()
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let data = input.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 210, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 12)
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 210, height: 260)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var statusPanel: some View {
        GlassPanel(tint: .black.opacity(0.04), cornerRadius: 22, padding: 18) {
            VStack(spacing: 12) {
                phaseSymbol
                Text(phase.title)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)

                if let message = phase.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var phaseSymbol: some View {
        switch phase {
        case .loading, .sending:
            ProgressView()
                .controlSize(.large)
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var actionPanel: some View {
        if phase.canRetry {
            HStack(spacing: 12) {
                SecondaryGlassButton(action: finish) {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                }

                PrimaryGlassButton {
                    Task { await send(input) }
                } label: {
                    Text("Try Again")
                        .frame(maxWidth: .infinity)
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
            try? await Task.sleep(nanoseconds: 650_000_000)
            finish()
        } else {
            phase = .failed(record.statusMessage)
        }
    }
}

private enum ShareSendPhase: Equatable {
    case loading
    case sending
    case sent(String)
    case failed(String)

    var title: String {
        switch self {
        case .loading:
            "Reading screenshot"
        case .sending:
            "Sending to Codex"
        case .sent:
            "Sent"
        case .failed:
            "Could not send"
        }
    }

    var message: String? {
        switch self {
        case .loading:
            "Preparing the shared image."
        case .sending:
            "Waiting for the relay."
        case .sent(let message), .failed(let message):
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
