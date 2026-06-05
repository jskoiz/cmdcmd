import SwiftUI

@main
struct CmdCmdApp: App {
    @State private var store = CaptureStore()
    @State private var isShowingSplash = true

    var body: some Scene {
        WindowGroup {
            Group {
                if isShowingSplash {
                    LaunchSplashView()
                } else {
                    ContentView(store: store)
                }
            }
            .task {
                await hideSplash()
            }
        }
    }

    @MainActor
    private func hideSplash() async {
        guard isShowingSplash else {
            return
        }

        try? await Task.sleep(nanoseconds: 850_000_000)
        withAnimation(.easeOut(duration: 0.18)) {
            isShowingSplash = false
        }
    }
}
