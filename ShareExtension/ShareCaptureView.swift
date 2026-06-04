import SwiftUI
import UIKit

struct ShareCaptureView: View {
    var loadInput: () async -> SharedCaptureInput
    var finish: () -> Void
    var cancel: () -> Void

    @State private var input = SharedCaptureInput()
    @State private var note = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var message = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewPanel
                    contextPanel
                    sendPanel
                }
                .padding(18)
            }
            .background {
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color.blue.opacity(0.10),
                        Color.teal.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .navigationTitle("cmd+cmd")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
            }
            .task {
                input = await loadInput()
                if !input.sourceText.isEmpty {
                    note = input.sourceText
                }
                isLoading = false
            }
        }
    }

    private var previewPanel: some View {
        GlassPanel(tint: .teal.opacity(0.16)) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Screenshot", systemImage: "photo")
                    .font(.headline)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let data = input.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    ContentUnavailableView("No image found", systemImage: "photo.badge.exclamationmark")
                        .frame(minHeight: 180)
                }
            }
        }
    }

    private var contextPanel: some View {
        GlassPanel(tint: .indigo.opacity(0.14)) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Context", systemImage: "text.bubble")
                    .font(.headline)

                TextField("What should Codex focus on?", text: $note, axis: .vertical)
                    .lineLimit(3...7)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var sendPanel: some View {
        GlassPanel(tint: .green.opacity(0.14), interactive: true) {
            VStack(alignment: .leading, spacing: 12) {
                PrimaryGlassButton {
                    Task { await send() }
                } label: {
                    Label(isSending ? "Sending" : "Send", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(input.imageData == nil || isSending)

                if !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func send() async {
        guard let data = input.imageData else { return }
        isSending = true
        message = "Preparing capture"
        let record = await CapturePipeline.submit(
            imageData: data,
            filename: input.filename.isEmpty ? "shared-screenshot.png" : input.filename,
            note: note,
            source: .shareExtension,
            sourceDetail: "Share Sheet"
        )
        message = record.statusMessage
        isSending = false

        if record.status == .sent || record.status == .needsEndpoint {
            finish()
        }
    }
}
