import SwiftUI

@main
struct CmdCmdRelayApp: App {
    @StateObject private var controller = RelayController()

    var body: some Scene {
        Window("cmd+cmd Relay", id: "main") {
            RelayDashboard(controller: controller)
                .frame(minWidth: 760, minHeight: 560)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("cmd+cmd Relay", systemImage: controller.isRunning ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle") {
            RelayMenu(controller: controller)
        }
    }
}

private struct RelayMenu: View {
    @ObservedObject var controller: RelayController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Relay") {
            openWindow(id: "main")
        }
        Divider()
        Text(controller.statusText)
        Text(controller.lastEvent)
        Divider()
        Button(controller.isRunning ? "Restart Relay" : "Start Relay") {
            controller.restart()
        }
        Button("Copy Pairing Link") {
            controller.copyPairingLink()
        }
        Button("Accessibility Settings") {
            controller.openAccessibilitySettings()
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}

