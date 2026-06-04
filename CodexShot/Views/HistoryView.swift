import SwiftUI
import UIKit

struct HistoryView: View {
    @Bindable var store: CaptureStore

    var body: some View {
        Group {
            if store.records.isEmpty {
                ContentUnavailableView("No captures", systemImage: "tray")
            } else {
                List {
                    ForEach(store.records) { record in
                        CaptureRecordRow(record: record)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    store.clearHistory()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.records.isEmpty)
                .accessibilityLabel("Clear history")
            }
        }
        .onAppear {
            store.reload()
        }
    }
}

private struct CaptureRecordRow: View {
    var record: CaptureRecord

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label(record.status.title, systemImage: record.status.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(record.status.tint)
                    Spacer()
                    Text(Formatters.relativeDate.localizedString(for: record.createdAt, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(record.userNote.isEmpty ? record.source.title : record.userNote)
                    .font(.subheadline)
                    .lineLimit(2)

                Text(record.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = record.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quinary)
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView(store: CaptureStore())
    }
}

