import SwiftUI
import UIKit

struct HistoryView: View {
    @Bindable var store: CaptureStore
    @State private var isConfirmingClear = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                header

                if store.records.isEmpty {
                    emptyState
                } else {
                    ForEach(store.records) { record in
                        CaptureRecordCard(record: record)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background { AppBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { store.reload() }
        .confirmationDialog(
            "Clear all captures?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                store.clearHistory()
            }
        } message: {
            Text("This removes the capture history on this iPhone. Screenshots already sent to Codex are not affected.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(store.records.isEmpty ? "No captures yet" : "\(store.records.count) capture\(store.records.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GlassIconButton(systemName: "trash", tint: store.records.isEmpty ? .secondary : .red) {
                isConfirmingClear = true
            }
            .disabled(store.records.isEmpty)
            .accessibilityLabel("Clear history")
        }
        .padding(.top, 6)
    }

    private var emptyState: some View {
        GlassPanel(tint: Theme.brandBright.opacity(0.10), cornerRadius: Theme.Radius.card, padding: 36) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.brand.opacity(0.12)).frame(width: 76, height: 76)
                    Image(systemName: "tray.and.arrow.up")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Theme.brand)
                }
                Text("No captures yet")
                    .font(.headline)
                Text("Screenshots you send to Codex will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 40)
    }
}

private struct CaptureRecordCard: View {
    var record: CaptureRecord

    var body: some View {
        GlassPanel(tint: .white.opacity(0.18), cornerRadius: Theme.Radius.panel, padding: 14) {
            HStack(spacing: 14) {
                thumbnail

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Label(record.status.title, systemImage: record.status.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(record.status.tint)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(record.status.tint.opacity(0.12), in: Capsule())
                        Spacer()
                        Text(Formatters.relativeDate.localizedString(for: record.createdAt, relativeTo: .now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(record.userNote.isEmpty ? record.source.title : record.userNote)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(record.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = record.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.brand.opacity(0.12))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.brand)
                }
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView(store: CaptureStore())
    }
}
