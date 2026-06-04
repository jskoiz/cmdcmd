import SwiftUI

struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        GlassPanel(tint: .white.opacity(0.22), interactive: true, cornerRadius: 36, padding: 8) {
            HStack(spacing: 8) {
                ForEach(AppTab.allCases) { tab in
                    FloatingTabButton(
                        tab: tab,
                        isSelected: selection == tab,
                        action: { selection = tab }
                    )
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 8)
    }
}

private struct FloatingTabButton: View {
    var tab: AppTab
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 21, weight: .semibold))
                Text(tab.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .teal : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.teal.opacity(0.14))
                }
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule()
                        .fill(Color.teal)
                        .frame(width: 16, height: 4)
                        .offset(y: 5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }
}
