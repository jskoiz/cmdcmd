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
                message: "Queued for the frontmost Codex chat",
                deliveryLane: "desktop-appshot"
            )
        )
    }

    func delivering(captureId: String) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "delivering",
                message: "Attaching to the frontmost Codex chat",
                deliveryLane: "desktop-appshot"
            )
        )
    }

    func delivered(captureId: String) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "delivered",
                message: "Attached phone screenshot in the frontmost Codex chat",
                deliveryLane: "desktop-appshot"
            )
        )
    }

    func failed(captureId: String, error: Error) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "failed",
                message: "Codex Desktop attach failed: \(Self.truncate(error.localizedDescription))",
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

