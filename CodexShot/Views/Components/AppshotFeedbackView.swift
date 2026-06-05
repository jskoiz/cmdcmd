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
            "Sent"
        case .failed:
            "Could not send"
        }
    }

    var symbolName: String {
        switch self {
        case .preparing:
            "sparkle"
        case .sending:
            "arrow.up"
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

    @State private var expanded = false
    @State private var spinning = false

    var body: some View {
        let metrics = layoutMetrics

        VStack(spacing: phase == .failed ? 8 : 12) {
            snapshot(width: metrics.previewWidth, height: metrics.previewHeight)
            statusLine
        }
        .padding(14)
        .frame(width: metrics.cardWidth)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Theme.glossOverlay)
                        .blendMode(.softLight)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.56), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 28, x: 0, y: 18)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        }
        .scaleEffect(expanded ? 1 : 0.04, anchor: .center)
        .opacity(expanded ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.73).delay(0.15), value: expanded)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: phase)
        .onAppear {
            AppshotFeedback.shared.prepare()
            spinning = phase.isWorking
            withAnimation(.spring(response: 0.35, dampingFraction: 0.73).delay(0.15)) {
                expanded = true
            }
        }
        .onChange(of: phase) { _, newPhase in
            spinning = newPhase.isWorking
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(phase.title)
    }

    private var previewImage: UIImage? {
        guard let imageData else {
            return nil
        }
        return UIImage(data: imageData)
    }

    private var previewAspectRatio: CGFloat {
        guard let previewImage else {
            return 19.5 / 9
        }

        let rawRatio = previewImage.size.height / max(previewImage.size.width, 1)
        return min(max(rawRatio, 1.45), 2.35)
    }

    private var layoutMetrics: (cardWidth: CGFloat, previewWidth: CGFloat, previewHeight: CGFloat) {
        let screen = UIScreen.main.bounds.size
        let cardWidth = min(max(screen.width - 52, 292), 340)
        let maxPreviewWidth = cardWidth - 42
        let maxPreviewHeight = min(max(screen.height * 0.70, 520), 620)

        var previewWidth = maxPreviewWidth
        var previewHeight = previewWidth * previewAspectRatio

        if previewHeight > maxPreviewHeight {
            previewHeight = maxPreviewHeight
            previewWidth = previewHeight / previewAspectRatio
        }

        return (cardWidth, previewWidth, previewHeight)
    }

    private func snapshot(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.76))
            }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.48), lineWidth: 1)

            if !phase.isWorking {
                phaseBadge
                    .padding(9)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            if phase.isWorking {
                workingRing
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: phase.symbolName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(phase.accent, in: Circle())
            }

            if phase == .failed, let message, !message.isEmpty {
                Text("\(phase.title) · \(message)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            } else {
                Text(phase.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var phaseBadge: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .frame(width: 34, height: 34)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.62), lineWidth: 1)
                }

            if phase.isWorking {
                workingRing
                    .frame(width: 19, height: 19)
            } else {
                Image(systemName: phase.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(phase.accent)
            }
        }
    }

    private var workingRing: some View {
        Circle()
            .trim(from: 0.12, to: 0.82)
            .stroke(
                Theme.brand,
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
            )
            .rotationEffect(spinning ? .degrees(360) : .degrees(0))
            .animation(
                spinning ? .linear(duration: 0.82).repeatForever(autoreverses: false) : .default,
                value: spinning
            )
    }
}

#Preview {
    ZStack {
        AppBackground()
        AppshotCaptureFeedbackView(
            phase: .sending,
            imageData: nil,
            message: nil
        )
    }
}
