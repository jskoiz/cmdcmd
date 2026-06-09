import OSLog
import SwiftUI

private let contentViewLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.jskoiz.CmdCmd",
    category: "ContentView"
)

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

    private func applyPairing(from url: URL) {
        guard let pairing = PairingLink.parse(url) else {
            contentViewLogger.error("pairing link rejected host=\(url.host() ?? "none", privacy: .public)")
            openSettings()
            return
        }

        contentViewLogger.info(
            "pairing link accepted endpointHost=\(URL(string: pairing.endpoint)?.host() ?? "invalid", privacy: .public) tokenSuffix=\(String(pairing.token.suffix(6)), privacy: .public)"
        )
        store.applyPairing(endpoint: pairing.endpoint, apiToken: pairing.token)
        openCapture()
    }
}

#Preview {
    ContentView(store: CaptureStore())
}
