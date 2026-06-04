import SwiftUI

struct SettingsView: View {
    @Bindable var store: CaptureStore
    @State private var draft = RelaySettings.empty
    @State private var savedMessage = ""

    var body: some View {
        Form {
            Section("Relay") {
                TextField("Endpoint URL", text: $draft.endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                SecureField("Bearer token", text: $draft.apiToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Context") {
                TextField("Default context", text: $draft.defaultContext, axis: .vertical)
                    .lineLimit(2...5)

                TextField("Thread hint", text: $draft.threadHint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Toggle("Include OCR text", isOn: $draft.includeRecognizedText)
            }

            Section {
                PrimaryGlassButton {
                    store.saveSettings(draft)
                    savedMessage = "Saved"
                } label: {
                    Label("Save Settings", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }

                if !savedMessage.isEmpty {
                    Text(savedMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            draft = store.settings
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(store: CaptureStore())
    }
}

