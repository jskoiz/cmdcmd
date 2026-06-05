import AVFoundation
import SwiftUI
import UIKit

enum AppshotSendFeedbackPhase: Equatable {
    case preparing
    case sending
    case sent
    case failed

    var title: String {
        switch self {
        case .preparing:
            "Preparing"
        case .sending:
            "Sending to Codex"
        case .sent:
            "AppShot sent to Codex"
        case .failed:
            "Could not send"
        }
    }

    var symbolName: String {
        switch self {
        case .preparing:
            "sparkle"
        case .sending:
            "paperplane.fill"
        case .sent:
            "checkmark"
        case .failed:
            "exclamationmark"
        }
    }

    var accent: Color {
        switch self {
        case .preparing, .sending:
            Theme.brand
        case .sent:
            .green
        case .failed:
            .orange
        }
    }

    var isWorking: Bool {
        self == .preparing || self == .sending
    }
}

@MainActor
final class AppshotFeedback {
    static let shared = AppshotFeedback()

    private var player: AVAudioPlayer?
    private let impact = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()

    private init() {}

    func prepare() {
        impact.prepare()
        notification.prepare()
        preparePlayer()
    }

    func playCaptureStart() {
        preparePlayer()
        player?.currentTime = 0
        player?.play()
        impact.impactOccurred(intensity: 0.72)
        impact.prepare()
    }

    func playCompletion(success: Bool) {
        notification.notificationOccurred(success ? .success : .error)
        notification.prepare()
    }

    private func preparePlayer() {
        guard player == nil else {
            player?.prepareToPlay()
            return
        }

        do {
            let soundData = Self.makeCaptureChime()
            let preparedPlayer = try AVAudioPlayer(data: soundData)
            preparedPlayer.volume = 0.74
            preparedPlayer.prepareToPlay()
            player = preparedPlayer
        } catch {
            player = nil
        }
    }

    private static func makeCaptureChime() -> Data {
        let sampleRate = 44_100
        let duration = 0.58
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: sampleCount * 4)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let attack = min(time / 0.012, 1)
            let release = min(max((duration - time) / 0.08, 0), 1)
            let click = sin(2 * .pi * 230 * time) * exp(-34 * time) * 0.20
            let body = sin(2 * .pi * 880 * time) * exp(-5.8 * time) * 0.25
            let delayedTime = max(time - 0.075, 0)
            let lift = time >= 0.075 ? sin(2 * .pi * 1_320 * delayedTime) * exp(-6.6 * delayedTime) * 0.20 : 0
            let shimmer = sin(2 * .pi * 1_760 * time) * exp(-10 * time) * 0.06
            let sample = (click + body + lift + shimmer) * attack * release

            appendPCM(sample * 0.96, to: &pcm)
            appendPCM(sample, to: &pcm)
        }

        var wav = Data(capacity: 44 + pcm.count)
        appendASCII("RIFF", to: &wav)
        appendLittleEndian(UInt32(36 + pcm.count), to: &wav)
        appendASCII("WAVE", to: &wav)
        appendASCII("fmt ", to: &wav)
        appendLittleEndian(UInt32(16), to: &wav)
        appendLittleEndian(UInt16(1), to: &wav)
        appendLittleEndian(UInt16(2), to: &wav)
        appendLittleEndian(UInt32(sampleRate), to: &wav)
        appendLittleEndian(UInt32(sampleRate * 4), to: &wav)
        appendLittleEndian(UInt16(4), to: &wav)
        appendLittleEndian(UInt16(16), to: &wav)
        appendASCII("data", to: &wav)
        appendLittleEndian(UInt32(pcm.count), to: &wav)
        wav.append(pcm)
        return wav
    }

    private static func appendPCM(_ sample: Double, to data: inout Data) {
        let clamped = min(max(sample, -1), 1)
        appendLittleEndian(Int16(clamped * Double(Int16.max)), to: &data)
    }

    private static func appendASCII(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

struct AppshotCaptureFeedbackView: View {
    var phase: AppshotSendFeedbackPhase
    var imageData: Data?
    var message: String?
    var openSettings: (() -> Void)?
    var settingsActionTitle = "Open Settings"

    var body: some View {
        statusPanel
            .frame(maxWidth: phase == .failed ? .infinity : 330, alignment: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: overlayAlignment)
            .padding(.bottom, phase == .failed ? 20 : 0)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .onAppear {
                AppshotFeedback.shared.prepare()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: phase == .failed ? 8 : 0) {
            HStack(alignment: .center, spacing: 10) {
                statusIcon

                Text(phase.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: phase == .failed ? .leading : .center)

            if phase == .failed {
                if let displayMessage {
                    Text(displayMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let openSettings {
                    Button(action: openSettings) {
                        Text(settingsActionTitle)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(phase.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens settings")
                }
            }
        }
        .padding(.horizontal, phase == .failed ? 18 : 16)
        .padding(.vertical, phase == .failed ? 16 : 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var statusIcon: some View {
        if phase.isWorking {
            ProgressView()
                .tint(phase.accent)
                .controlSize(.small)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: phase.symbolName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(phase.accent, in: Circle())
        }
    }

    private var displayMessage: String? {
        guard var cleaned = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else {
            return nil
        }

        for prefix in ["Codex Desktop attach failed: ", "Could not send AppShot: "] {
            if cleaned.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
                cleaned.removeFirst(prefix.count)
                break
            }
        }
        return cleaned
    }

    private var accessibilityLabel: String {
        if let displayMessage {
            return "\(phase.title). \(displayMessage)"
        }
        return phase.title
    }

    private var overlayAlignment: Alignment {
        phase == .failed ? .bottom : .center
    }

    private var panelFill: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 0.96)
            }
            return UIColor.white.withAlphaComponent(0.96)
        })
    }

}

#Preview {
    ZStack {
        AppBackground()
        AppshotCaptureFeedbackView(
            phase: .failed,
            imageData: nil,
            message: "Relay rejected the capture with HTTP 401: {\"error\":\"unauthorized.\"}",
            openSettings: {}
        )
    }
}
