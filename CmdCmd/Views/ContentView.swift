import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case capture
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture:
            "Capture"
        case .history:
            "History"
        case .settings:
            "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .capture:
            "camera.fill"
        case .history:
            "clock"
        case .settings:
            "gearshape"
        }
    }
}

struct ContentView: View {
    @Bindable var store: CaptureStore
    @State private var selectedTab: AppTab = .capture

    var body: some View {
        ZStack(alignment: .topTrailing) {
            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            AppNavigationMenu(selection: $selectedTab)
                .padding(.top, 18)
                .padding(.trailing, 22)
        }
        .tint(Theme.brand)
        .onOpenURL { url in
            switch AppDeepLink.parse(url) {
            case .settings:
                openSettings()
            case nil:
                return
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .capture:
            NavigationStack {
                CaptureView(
                    store: store,
                    openSettings: openSettings
                )
            }
        case .history:
            NavigationStack {
                HistoryView(store: store)
            }
        case .settings:
            NavigationStack {
                SettingsView(store: store, onFinished: openCapture)
            }
        }
    }

    private func openCapture() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            selectedTab = .capture
        }
    }

    private func openSettings() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            selectedTab = .settings
        }
    }

}

#Preview {
    ContentView(store: CaptureStore())
}
