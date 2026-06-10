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
            "Screenshot sent to Codex"
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
        prepareAudioSession()
        impact.prepare()
        notification.prepare()
        preparePlayer()
    }

    func playCaptureStart() {
        prepareAudioSession()
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

    private func prepareAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Haptics should still fire if the extension host refuses audio activation.
        }
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
    var imageCount = 1
    var message: String?
    var openSettings: (() -> Void)?
    var settingsActionTitle = "Open Settings"

    var body: some View {
        feedbackContent
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

    private var feedbackContent: some View {
        VStack(spacing: phase == .failed ? 14 : 16) {
            imagePreview
            statusPanel
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            GeometryReader { proxy in
                let size = previewSize(for: image, in: proxy.size)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(0.36), lineWidth: 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        imageCountBadge
                            .padding(12)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 14)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
            .frame(height: phase == .failed ? 430 : 460)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var imageCountBadge: some View {
        if imageCount > 1 {
            HStack(spacing: 5) {
                Image(systemName: "photo.stack")
                    .font(.caption2.weight(.bold))
                Text("\(imageCount)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.black.opacity(0.58), in: Capsule())
        }
    }

    @ViewBuilder
    private var statusPanel: some View {
        if phase == .failed {
            failureStatusPanel
        } else {
            workingStatusPanel
        }
    }

    private var workingStatusPanel: some View {
        CommandDeliveryStatusView(phase: phase)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
    }

    private var failureStatusPanel: some View {
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

    private func previewSize(for image: UIImage, in containerSize: CGSize) -> CGSize {
        containerSize.aspectFitting(imageSize: image.size)
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

        for prefix in ["Codex Desktop attach failed: ", "Could not send screenshot: "] {
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

private struct CommandDeliveryStatusView: View {
    var phase: AppshotSendFeedbackPhase

    @State private var isRotating = false
    @State private var isCollapsed = false
    @State private var isShowingCheckmark = false

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                commandSymbol(side: .left)
                plusSymbol
                commandSymbol(side: .right)
                checkmark
            }
            .frame(width: 124, height: 42)

            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            applyPhase(animated: false)
        }
        .onChange(of: phase) { _, _ in
            applyPhase(animated: true)
        }
    }

    @ViewBuilder
    private func commandSymbol(side: CommandSide) -> some View {
        Image(systemName: "command")
            .font(.system(size: 25, weight: .bold, design: .rounded))
            .foregroundStyle(phase == .sent ? .green : phase.accent)
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(isRotating ? side.rotationDegrees : 0))
            .offset(x: isCollapsed ? 0 : side.offset)
            .scaleEffect(isCollapsed ? 0.72 : 1)
            .opacity(isShowingCheckmark ? 0 : 1)
            .animation(
                isRotating ? .linear(duration: 3.4).repeatForever(autoreverses: false) : .easeOut(duration: 0.18),
                value: isRotating
            )
            .animation(.spring(response: 0.48, dampingFraction: 0.82), value: isCollapsed)
            .animation(.easeOut(duration: 0.16), value: isShowingCheckmark)
    }

    private var plusSymbol: some View {
        Text("+")
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundStyle(phase == .sent ? .green : phase.accent)
            .frame(width: 24, height: 30)
            .scaleEffect(isCollapsed ? 0.72 : 1)
            .opacity(isShowingCheckmark ? 0 : 1)
            .animation(.spring(response: 0.48, dampingFraction: 0.82), value: isCollapsed)
            .animation(.easeOut(duration: 0.16), value: isShowingCheckmark)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 21, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(.green, in: Circle())
            .scaleEffect(isShowingCheckmark ? 1 : 0.64)
            .opacity(isShowingCheckmark ? 1 : 0)
            .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isShowingCheckmark)
    }

    private var subtitle: String {
        // Mirrors phase.title, but uses shorter copy for .sent so it fits one line.
        phase == .sent ? "Sent to Codex" : phase.title
    }

    private func applyPhase(animated: Bool) {
        switch phase {
        case .preparing, .sending:
            isShowingCheckmark = false
            isCollapsed = false
            isRotating = true
        case .sent:
            isRotating = false
            let collapse = {
                isCollapsed = true
            }

            if animated {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.82), collapse)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                        isShowingCheckmark = true
                    }
                }
            } else {
                collapse()
                isShowingCheckmark = true
            }
        case .failed:
            isRotating = false
            isCollapsed = false
            isShowingCheckmark = false
        }
    }

    private enum CommandSide {
        case left
        case right

        var offset: CGFloat {
            switch self {
            case .left:
                -42
            case .right:
                42
            }
        }

        var rotationDegrees: Double {
            switch self {
            case .left:
                360
            case .right:
                -360
            }
        }
    }
}

extension CGSize {
    /// Largest size preserving `imageSize`'s aspect ratio that fits within this size.
    func aspectFitting(imageSize: CGSize) -> CGSize {
        let availableWidth = max(width, 1)
        let availableHeight = max(height, 1)
        let aspectRatio = max(imageSize.width, 1) / max(imageSize.height, 1)

        var fittedWidth = availableWidth
        var fittedHeight = fittedWidth / aspectRatio
        if fittedHeight > availableHeight {
            fittedHeight = availableHeight
            fittedWidth = fittedHeight * aspectRatio
        }

        return CGSize(width: fittedWidth, height: fittedHeight)
    }
}

#Preview {
    ZStack {
        AppBackground()
        AppshotCaptureFeedbackView(
            phase: .sending,
            imageData: nil,
            message: "Relay rejected the capture with HTTP 401: {\"error\":\"unauthorized.\"}",
            openSettings: {}
        )
    }
}
