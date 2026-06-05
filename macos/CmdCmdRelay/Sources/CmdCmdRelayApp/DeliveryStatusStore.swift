import Foundation

struct DeliveryStatus: Codable, Equatable {
    var captureId: String
    var status: String
    var message: String
    var deliveryLane: String?
}

final class DeliveryStatusStore {
    private var statuses: [String: DeliveryStatus] = [:]
    private let lock = NSLock()

    func accept(captureId: String) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "accepted",
                message: "AppShot queued for Codex",
                deliveryLane: "desktop-appshot"
            )
        )
    }

    func delivering(captureId: String) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "delivering",
                message: "Sending AppShot to Codex",
                deliveryLane: "desktop-appshot"
            )
        )
    }

    func delivered(captureId: String) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "delivered",
                message: "AppShot sent to Codex",
                deliveryLane: "desktop-appshot"
            )
        )
    }

    func failed(captureId: String, error: Error) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "failed",
                message: "Could not send AppShot: \(Self.truncate(error.localizedDescription))",
                deliveryLane: "desktop-appshot"
            )
        )
    }

    func status(captureId: String) -> DeliveryStatus? {
        lock.lock()
        defer { lock.unlock() }
        return statuses[captureId]
    }

    private func set(_ status: DeliveryStatus) {
        lock.lock()
        statuses[status.captureId] = status
        lock.unlock()
    }

    private static func truncate(_ value: String, limit: Int = 240) -> String {
        if value.count <= limit {
            return value
        }
        return "\(value.prefix(limit))..."
    }
}

