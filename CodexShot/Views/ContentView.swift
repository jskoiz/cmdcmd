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
        ZStack(alignment: .bottom) {
            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 88)
                }

            FloatingTabBar(selection: $selectedTab, settingsNeedsAttention: !store.hasEndpoint)
        }
        .tint(Theme.brand)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .capture:
            NavigationStack {
                CaptureView(store: store)
            }
        case .history:
            NavigationStack {
                HistoryView(store: store)
            }
        case .settings:
            NavigationStack {
                SettingsView(store: store)
            }
        }
    }
}

#Preview {
    ContentView(store: CaptureStore())
}
