import SwiftUI

struct SettingsView: View {
    @Bindable var store: CaptureStore
    @State private var draft = RelaySettings.empty
    @State private var savedMessage = ""
    @State private var relayCheckMessage = ""
    @State private var isCheckingRelay = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                header

                SettingsCard(title: "Relay", icon: "antenna.radiowaves.left.and.right", tint: Theme.brand) {
                    SettingsField(label: "Endpoint URL") {
                        TextField("https://relay.local", text: $draft.endpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    Divider().overlay(.white.opacity(0.25))
                    SettingsField(label: "Bearer token") {
                        SecureField("••••••••", text: $draft.apiToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Divider().overlay(.white.opacity(0.25))
                    relayCheckRow
                }

                SettingsCard(title: "Context", icon: "text.alignleft", tint: Theme.accentBlue) {
                    SettingsField(label: "Default context") {
                        TextField("e.g. Review this networking error", text: $draft.defaultContext, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    Divider().overlay(.white.opacity(0.25))
                    Toggle(isOn: $draft.includeRecognizedText) {
                        Text("Include OCR text")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(Theme.brand)
                }

                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background { AppBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { draft = store.settings }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Configure your private cmd+cmd relay")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private var saveButton: some View {
        VStack(spacing: 10) {
            HeroSendButton {
                store.saveSettings(draft)
                withAnimation { savedMessage = "Settings saved" }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                    Text("Save Settings")
                        .font(.title3.weight(.semibold))
                }
            }

            if !savedMessage.isEmpty {
                Label(savedMessage, systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.brandDeep)
                    .transition(.opacity)
            }
        }
        .padding(.top, 4)
    }

    private var relayCheckRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await testRelayConnection() }
            } label: {
                HStack(spacing: 8) {
                    if isCheckingRelay {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "network")
                    }
                    Text(isCheckingRelay ? "Checking Relay" : "Test Connection")
                }
                .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.brandDeep)
            .disabled(isCheckingRelay)

            if !relayCheckMessage.isEmpty {
                Text(relayCheckMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func testRelayConnection() async {
        isCheckingRelay = true
        relayCheckMessage = ""
        let message = await RelayDiagnostics.check(endpoint: draft.endpoint)
        relayCheckMessage = message
        isCheckingRelay = false
    }
}

private enum RelayDiagnostics {
    static func check(endpoint: String) async -> String {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            return "Add a relay endpoint before testing."
        }

        guard let url = healthURL(for: trimmedEndpoint) else {
            return "The relay endpoint is not a valid URL."
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return "Relay responded without an HTTP status."
            }

            if (200..<300).contains(httpResponse.statusCode) {
                return "Relay is reachable at \(url.host() ?? trimmedEndpoint)."
            }

            return "Relay health check returned HTTP \(httpResponse.statusCode)."
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorNotConnectedToInternet {
                return CaptureFailurePresentation.relayReachabilityMessage(endpoint: trimmedEndpoint)
            }

            return error.localizedDescription
        }
    }

    private static func healthURL(for endpoint: String) -> URL? {
        guard var components = URLComponents(string: endpoint),
              let scheme = components.scheme,
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return nil
        }

        components.path = "/healthz"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String
    var icon: String
    var tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)

            GlassPanel(tint: .white.opacity(0.18), cornerRadius: Theme.Radius.panel, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
            }
        }
    }
}

private struct SettingsField<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
                .font(.body)
                .textFieldStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(store: CaptureStore())
    }
}
