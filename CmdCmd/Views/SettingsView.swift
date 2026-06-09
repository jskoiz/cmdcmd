import AVFoundation
import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var store: CaptureStore
    var onFinished: () -> Void = {}
    @State private var draft = RelaySettings.empty
    @State private var savedMessage = ""
    @State private var showsManualRelay = false
    @State private var relayCheckMessage = ""
    @State private var isCheckingRelay = false
    @State private var showsPairingScanner = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                header

                SettingsCard(title: "Desktop", icon: "desktopcomputer", tint: Theme.brand) {
                    HStack(alignment: .center, spacing: 12) {
                        ConnectionStatusDot(isConnected: hasDraftEndpoint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hasDraftEndpoint ? "Ready" : "Not paired")
                                .font(.headline.weight(.semibold))
                            Text(hasDraftEndpoint ? endpointHost : "Finish on your Mac")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                    }

                    if !hasDraftEndpoint {
                        DesktopOnboardingPrompt(siteURL: setupSiteURL) {
                            showsPairingScanner = true
                        }
                    }

                    if hasDraftEndpoint {
                        Divider().overlay(.white.opacity(0.25))
                        relayCheckRow
                        Button {
                            showsPairingScanner = true
                        } label: {
                            Label("Scan New QR", systemImage: "qrcode.viewfinder")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.brandDeep)
                    }

                    DisclosureGroup(isExpanded: $showsManualRelay) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsField(label: "Relay URL") {
                                TextField("Optional", text: $draft.endpoint)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                            }
                            Divider().overlay(.white.opacity(0.25))
                            SettingsField(label: "Token") {
                                SecureField("Optional", text: $draft.apiToken)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Manual relay")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.brandDeep)
                    }
                    .tint(Theme.brand)
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

                SettingsCard(title: "Info", icon: "info.circle", tint: Theme.tertiaryText) {
                    DebugInfoRow(label: "Version", value: appVersionLabel)
                    Divider().overlay(.white.opacity(0.25))
                    DebugInfoRow(label: "Relay", value: hasDraftEndpoint ? endpointHost : "Not paired")
                    Divider().overlay(.white.opacity(0.25))
                    DebugInfoRow(label: "Token", value: tokenDebugLabel)
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
        .sheet(isPresented: $showsPairingScanner) {
            PairingScannerSheet { pairing in
                applyPairing(pairing)
            }
        }
    }

    private var hasDraftEndpoint: Bool {
        !draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var endpointHost: String {
        URL(string: draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host() ?? "Manual relay"
    }

    private var setupSiteURL: String {
        "https://cmd.avmil.xyz"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Desktop connection and defaults")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 6)
    }

    private var saveButton: some View {
        VStack(spacing: 10) {
            HeroSendButton {
                store.saveSettings(draft)
                withAnimation { savedMessage = "Settings saved" }
                onFinished()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                    Text("Save")
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
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func testRelayConnection() async {
        isCheckingRelay = true
        relayCheckMessage = ""
        relayCheckMessage = await RelayClient(settings: draft).checkReadiness().message
        isCheckingRelay = false
    }

    @MainActor
    private func applyPairing(_ pairing: PairingLink) {
        draft.endpoint = pairing.endpoint
        draft.apiToken = pairing.token
        relayCheckMessage = ""
        showsManualRelay = false
        store.applyPairing(endpoint: pairing.endpoint, apiToken: pairing.token)
        withAnimation { savedMessage = "Desktop linked" }
    }
}

private struct ConnectionStatusDot: View {
    var isConnected: Bool

    var body: some View {
        Circle()
            .fill(isConnected ? Color.green : Color(.systemGray3))
            .frame(width: 10, height: 10)
            .padding(7)
            .background(Color(.tertiarySystemFill), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct DesktopOnboardingPrompt: View {
    var siteURL: String
    var scanAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SetupStep(
                number: "1",
                title: "Open the setup site on your Mac",
                detail: siteURL
            )
            SetupStep(
                number: "2",
                title: "Run the install command",
                detail: "The installer starts the Desktop relay and prints a private pairing QR."
            )
            SetupStep(
                number: "3",
                title: "Scan the QR here",
                detail: "This fills the relay endpoint and token on this iPhone."
            )

            Button(action: scanAction) {
                Label("Scan Desktop QR", systemImage: "qrcode.viewfinder")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Theme.sendGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                Theme.glossOverlay
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct SetupStep: View {
    var number: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.brandDeep, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(number == "1" ? .system(.subheadline, design: .monospaced).weight(.semibold) : .subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PairingScannerSheet: View {
    var onPair: (PairingLink) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scanMessage = "Point the camera at the QR shown in Terminal."
    @State private var cameraError = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PairingQRCodeScanner { rawValue in
                    guard let pairing = PairingLink.parse(rawValue) else {
                        scanMessage = "That is not a cmd+cmd Desktop pairing QR."
                        return false
                    }

                    onPair(pairing)
                    dismiss()
                    return true
                } onError: { message in
                    cameraError = message
                    scanMessage = message
                }
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(.white.opacity(0.9), lineWidth: 2)
                        )
                        .accessibilityHidden(true)

                    Text(scanMessage)
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.58))
            }
            .navigationTitle("Scan Desktop QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Camera unavailable", isPresented: Binding(
                get: { !cameraError.isEmpty },
                set: { if !$0 { cameraError = "" } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cameraError)
            }
        }
    }
}

private struct PairingQRCodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Bool
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> PairingScannerViewController {
        let controller = PairingScannerViewController()
        controller.onCode = onCode
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: PairingScannerViewController, context: Context) {
        uiViewController.onCode = onCode
        uiViewController.onError = onError
    }
}

private final class PairingScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Bool)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didCompleteScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        prepareCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func prepareCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureSession()
                    } else {
                        self.onError?("Camera permission is required to scan the Desktop pairing QR.")
                    }
                }
            }
        case .denied, .restricted:
            onError?("Camera permission is required to scan the Desktop pairing QR.")
        @unknown default:
            onError?("Camera permission is unavailable.")
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            onError?("No camera is available on this device.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                onError?("The camera could not be added to the scanner.")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onError?("QR scanning is unavailable on this device.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer

            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private func stopSession() {
        guard session.isRunning else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didCompleteScan,
              let object = metadataObjects
                .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                .first(where: { $0.type == .qr }),
              let value = object.stringValue else {
            return
        }

        if onCode?(value) == true {
            didCompleteScan = true
            stopSession()
        }
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
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
            content
                .font(.body)
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
        }
    }
}

private struct DebugInfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
            Spacer(minLength: 14)
            Text(value)
                .font(.subheadline.monospaced().weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
    }
}

private extension SettingsView {
    var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    var tokenDebugLabel: String {
        let token = draft.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return "Not set"
        }
        return "Set ...\(token.suffix(6))"
    }
}

#Preview {
    NavigationStack {
        SettingsView(store: CaptureStore())
    }
}
