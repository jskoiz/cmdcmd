import SwiftUI

@main
struct CmdCmdApp: App {
    @State private var store = CaptureStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}

