import SwiftUI

struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var settingsNeedsAttention: Bool
    @Namespace private var indicator

    var body: some View {
        GlassPanel(tint: .white.opacity(0.12), interactive: true, cornerRadius: 34, padding: 6) {
            HStack(spacing: 4) {
                ForEach(AppTab.allCases) { tab in
                    FloatingTabButton(
                        tab: tab,
                        isSelected: selection == tab,
                        showsBadge: tab == .settings && settingsNeedsAttention,
                        namespace: indicator,
                        action: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                selection = tab
                            }
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }
}

private struct FloatingTabButton: View {
    var tab: AppTab
    var isSelected: Bool
    var showsBadge: Bool
    var namespace: Namespace.ID
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolEffect(.bounce, value: isSelected)

                    if showsBadge {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 5, y: -3)
                    }
                }
                Text(tab.title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? Theme.brandDeep : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.brand.opacity(0.08))
                        .overlay { Capsule().strokeBorder(Theme.brand.opacity(0.12), lineWidth: 1) }
                        .matchedGeometryEffect(id: "tabSelection", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsBadge ? "\(tab.title), needs attention" : tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
