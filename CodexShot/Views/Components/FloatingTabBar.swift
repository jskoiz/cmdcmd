import SwiftUI

struct AppNavigationMenu: View {
    @Binding var selection: AppTab
    var settingsNeedsAttention: Bool

    var body: some View {
        Menu {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        selection = tab
                    }
                } label: {
                    Label(tab.title, systemImage: tab.symbolName)
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().strokeBorder(Theme.brand.opacity(0.10), lineWidth: 1) }

                if settingsNeedsAttention {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settingsNeedsAttention ? "Options, settings needs attention" : "Options")
    }
}
