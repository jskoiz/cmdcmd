import SwiftUI

struct AppNavigationMenu: View {
    @Binding var selection: AppTab

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
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary.opacity(0.88))
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemBackground).opacity(0.46), in: Circle())
                .overlay { Circle().strokeBorder(Theme.brand.opacity(0.06), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Options")
    }
}
