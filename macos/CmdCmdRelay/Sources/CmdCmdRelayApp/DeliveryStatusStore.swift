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

    func accept(captureId: String, deliveryMode: RelayDeliveryMode = .codex) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "accepted",
                message: copy(for: deliveryMode).accepted,
                deliveryLane: deliveryMode.lane
            )
        )
    }

    func delivering(captureId: String, deliveryMode: RelayDeliveryMode = .codex) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "delivering",
                message: copy(for: deliveryMode).delivering,
                deliveryLane: deliveryMode.lane
            )
        )
    }

    func delivered(captureId: String, deliveryMode: RelayDeliveryMode = .codex) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "delivered",
                message: copy(for: deliveryMode).delivered,
                deliveryLane: deliveryMode.lane
            )
        )
    }

    func failed(captureId: String, error: Error, deliveryMode: RelayDeliveryMode = .codex) {
        set(
            DeliveryStatus(
                captureId: captureId,
                status: "failed",
                message: "\(copy(for: deliveryMode).failedPrefix): \(Self.truncate(error.localizedDescription))",
                deliveryLane: deliveryMode.lane
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

    private func copy(for deliveryMode: RelayDeliveryMode) -> StatusCopy {
        switch deliveryMode {
        case .codex:
            return StatusCopy(
                accepted: "Screenshot queued for Codex",
                delivering: "Sending screenshot to Codex",
                delivered: "Screenshot sent to Codex",
                failedPrefix: "Could not send screenshot"
            )
        case .reviewInbox:
            return StatusCopy(
                accepted: "Screenshot queued for review inbox",
                delivering: "Saving screenshot to review inbox",
                delivered: "Screenshot saved to review inbox",
                failedPrefix: "Could not save screenshot"
            )
        }
    }
}

private struct StatusCopy {
    var accepted: String
    var delivering: String
    var delivered: String
    var failedPrefix: String
}

private extension RelayDeliveryMode {
    var lane: String {
        switch self {
        case .codex:
            return "desktop-attachment"
        case .reviewInbox:
            return "review-inbox"
        }
    }
}
