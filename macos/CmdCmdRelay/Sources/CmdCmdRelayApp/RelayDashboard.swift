import SwiftUI

struct RelayDashboard: View {
    @ObservedObject var controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshAccessibilityTrust(prompt: false)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 8) {
                Text("cmd+cmd Relay")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                Text("Private phone screenshot delivery into the frontmost Codex chat.")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            RelayStatusPill(isRunning: controller.isRunning, text: controller.statusText)
        }
        .padding(28)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 22) {
                section("Pair") {
                    FieldRow(title: "Endpoint", value: controller.endpointForDisplay) {
                        controller.copyEndpoint()
                    }
                    FieldRow(title: "Bearer token", value: controller.tokenForDisplay) {
                        controller.copyToken()
                    }

                    HStack(spacing: 10) {
                        Button(controller.tokenVisible ? "Hide Token" : "Reveal Token") {
                            controller.tokenVisible.toggle()
                        }
                        Button("Rotate Token") {
                            controller.rotateToken()
                        }
                        Button("Copy Pairing Link") {
                            controller.copyPairingLink()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                section("Network") {
                    Toggle("Allow iPhone on private network", isOn: Binding(
                        get: { controller.settings.listensOnPrivateNetwork },
                        set: { controller.setPrivateNetworkEnabled($0) }
                    ))
                    .toggleStyle(.switch)

                    Text(controller.settings.listensOnPrivateNetwork
                         ? "Reachable from devices on this trusted network with the bearer token."
                         : "Localhost only. Use this for simulator testing.")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                section("Permissions") {
                    HStack(spacing: 12) {
                        Image(systemName: controller.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        Text(controller.accessibilityTrusted ? "Accessibility permission granted" : "Accessibility permission required")
                        Spacer()
                        Button("Open Settings") {
                            controller.openAccessibilitySettings()
                        }
                    }
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 18) {
                QRPanel(image: controller.qrImage)
                section("Status") {
                    Text(controller.lastEvent)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        Button(controller.isRunning ? "Restart" : "Start") {
                            controller.restart()
                        }
                        Button("Reveal Inbox") {
                            controller.revealInbox()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(width: 240, alignment: .topLeading)
        }
        .padding(28)
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(.top, 4)
    }
}

private struct RelayStatusPill: View {
    var isRunning: Bool
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? Color.black : Color.secondary)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct FieldRow: View {
    var title: String
    var value: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 10) {
                Text(value)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.16), lineWidth: 1)
            )
        }
    }
}

private struct QRPanel: View {
    var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAIR IPHONE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            ZStack {
                Rectangle()
                    .fill(Color.white)
                if let image {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                }
            }
            .frame(width: 220, height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1)
            )

            Text("Scan from iPhone after installing cmd+cmd.")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

