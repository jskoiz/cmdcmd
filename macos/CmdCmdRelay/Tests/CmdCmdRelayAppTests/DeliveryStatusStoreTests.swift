import Foundation
import XCTest
@testable import CmdCmdRelayApp

final class DeliveryStatusStoreTests: XCTestCase {
    func testTwoHundredFirstUniqueStatusEvictsOldest() {
        let store = DeliveryStatusStore()

        for index in 0..<201 {
            store.accept(captureId: "capture-\(index)")
        }

        XCTAssertEqual(store.count, 200)
        XCTAssertNil(store.status(captureId: "capture-0"))
        XCTAssertEqual(store.status(captureId: "capture-200")?.status, "accepted")
    }

    func testUpdatingExistingStatusPreservesTransitionsAndCount() {
        let store = DeliveryStatusStore()

        store.accept(captureId: "capture")
        store.delivering(captureId: "capture")
        store.delivered(captureId: "capture")

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(
            store.status(captureId: "capture"),
            DeliveryStatus(
                captureId: "capture",
                status: "delivered",
                message: "Screenshot sent to Codex",
                deliveryLane: "desktop-attachment"
            )
        )
    }

    func testConcurrentReadersAndWritersRetainAtMostTwoHundred() {
        let store = DeliveryStatusStore()
        let queue = DispatchQueue(label: "DeliveryStatusStoreTests", attributes: .concurrent)
        let group = DispatchGroup()

        for index in 0..<500 {
            group.enter()
            queue.async {
                store.accept(captureId: "capture-\(index)")
                _ = store.status(captureId: "capture-\(index)")
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertLessThanOrEqual(store.count, 200)
    }
}
