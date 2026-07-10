import Foundation
import XCTest
@testable import CmdCmdRelayApp

final class DeliveryStatusStoreTests: XCTestCase {
    func testTwoHundredFirstUniqueStatusEvictsOldest() {
        let store = DeliveryStatusStore()
        for index in 0..<201 {
            store.accept(captureId: "capture-\(index)")
        }

        XCTAssertNil(store.status(captureId: "capture-0"))
        XCTAssertEqual(store.status(captureId: "capture-1")?.status, "accepted")
        XCTAssertEqual(store.status(captureId: "capture-200")?.status, "accepted")
        XCTAssertEqual(store.count, 200)
    }

    func testUpdatingExistingStatusPreservesTransitionsAndCount() {
        let store = DeliveryStatusStore()
        for index in 0..<200 {
            store.accept(captureId: "capture-\(index)")
        }

        store.delivering(captureId: "capture-0")
        store.delivered(captureId: "capture-0")

        XCTAssertEqual(store.status(captureId: "capture-0")?.status, "delivered")
        XCTAssertEqual(store.count, 200)

        store.accept(captureId: "capture-200")
        XCTAssertNil(store.status(captureId: "capture-0"))
        XCTAssertNotNil(store.status(captureId: "capture-1"))
        XCTAssertEqual(store.count, 200)
    }

    func testConcurrentReadersAndWritersRetainAtMostTwoHundred() {
        let store = DeliveryStatusStore()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "app.cmdcmd.relay.status-tests", attributes: .concurrent)

        for index in 0..<1_000 {
            group.enter()
            queue.async {
                store.accept(captureId: "capture-\(index)")
                store.delivering(captureId: "capture-\(index)")
                _ = store.status(captureId: "capture-\(index / 2)")
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertLessThanOrEqual(store.count, 200)
    }
}
