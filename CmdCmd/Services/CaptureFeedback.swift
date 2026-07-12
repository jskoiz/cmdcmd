import AVFoundation
import Foundation
import UIKit

@MainActor
final class CaptureFeedback {
    static let shared = CaptureFeedback()

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
