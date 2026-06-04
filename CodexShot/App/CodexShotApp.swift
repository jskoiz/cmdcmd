import SwiftUI

@main
struct CodexShotApp: App {
    @State private var store = CaptureStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}

