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

            AppNavigationMenu(selection: $selectedTab, settingsNeedsAttention: !store.hasEndpoint)
                .padding(.top, 18)
                .padding(.trailing, 22)
        }
        .tint(Theme.brand)
        .onOpenURL { url in
            guard url.scheme == "cmdcmd" else {
                return
            }

            switch url.host() {
            case "pair":
                applyPairing(from: url)
            case "settings":
                openSettings()
            default:
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
                SettingsView(store: store)
            }
        }
    }

    private func openSettings() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            selectedTab = .settings
        }
    }

    private func applyPairing(from url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            openSettings()
            return
        }

        let endpoint = components.queryItems?
            .first(where: { $0.name == "endpoint" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = components.queryItems?
            .first(where: { $0.name == "token" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !endpoint.isEmpty, !token.isEmpty else {
            openSettings()
            return
        }

        store.applyPairing(endpoint: endpoint, apiToken: token)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            selectedTab = .capture
        }
    }
}

#Preview {
    ContentView(store: CaptureStore())
}
