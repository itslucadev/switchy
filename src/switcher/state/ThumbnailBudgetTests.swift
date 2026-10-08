import Cocoa
import XCTest

final class ThumbnailBudgetTests: XCTestCase {
    private let tenMiB: UInt64 = 10 * 1024 * 1024

    private func store(
        _ budget: ThumbnailBudget, _ ids: ClosedRange<Int>, bytes: UInt64,
        protecting: Set<CGWindowID> = []
    ) {
        for id in ids {
            _ = budget.store(CGWindowID(id), bytes: bytes, protecting: protecting)
        }
    }

    /// The 21st stored id drops the least recently used id; the other twenty remain.
    func testCountEvictionDropsTheLeastRecentlyStoredId() {
        let budget = ThumbnailBudget()
        store(budget, 1...21, bytes: 1)
        XCTAssertFalse(budget.contains(1))
        XCTAssertEqual(budget.count, 20)
        for id in 2...21 {
            XCTAssertTrue(budget.contains(CGWindowID(id)), "expected \(id) cached")
        }
    }

    /// Ids whose bytes exceed 32 MiB drop least recently used ids until the remainder fits.
    func testByteBudgetEvictsLeastRecentlyUsedIds() {
        let budget = ThumbnailBudget()
        store(budget, 1...7, bytes: tenMiB)
        XCTAssertFalse(budget.contains(1))
        XCTAssertFalse(budget.contains(2))
        XCTAssertFalse(budget.contains(3))
        XCTAssertFalse(budget.contains(4))
        for id in 5...7 {
            XCTAssertTrue(budget.contains(CGWindowID(id)), "expected \(id) cached")
        }
        XCTAssertEqual(budget.totalBytes, 30 * 1024 * 1024)
    }

    /// Storing a smaller size for an existing id frees the old bytes so a later size can fit.
    func testReplacingAnIdReleasesItsOldBytes() {
        let budget = ThumbnailBudget()
        store(budget, 1...3, bytes: tenMiB)
        _ = budget.store(3, bytes: 20 * 1024 * 1024)
        XCTAssertFalse(budget.contains(1))
        XCTAssertTrue(budget.contains(2))
        XCTAssertTrue(budget.contains(3))
        XCTAssertEqual(budget.totalBytes, 30 * 1024 * 1024)
    }

    /// `touch` promotes that id so a later store evicts a different least-recently-used id.
    func testTouchProtectsFromCountEviction() {
        let budget = ThumbnailBudget()
        store(budget, 1...20, bytes: 1)
        budget.touch(1)
        _ = budget.store(21, bytes: 1)
        XCTAssertTrue(budget.contains(1))
        XCTAssertFalse(budget.contains(2))
        XCTAssertTrue(budget.contains(21))
    }

    /// An id larger than 32 MiB evicts every older id and remains cached.
    func testOversizedNewestIdIsRetainedAlone() {
        let budget = ThumbnailBudget()
        store(budget, 1...3, bytes: tenMiB)
        _ = budget.store(4, bytes: 70 * 1024 * 1024)
        XCTAssertFalse(budget.contains(1))
        XCTAssertFalse(budget.contains(2))
        XCTAssertFalse(budget.contains(3))
        XCTAssertTrue(budget.contains(4))
        XCTAssertEqual(budget.count, 1)
        XCTAssertEqual(budget.totalBytes, 70 * 1024 * 1024)
    }

    /// Ids in `protecting` survive a store that would otherwise evict them.
    func testProtectedIdsAreNotEvicted() {
        let budget = ThumbnailBudget()
        store(budget, 1...20, bytes: 1)
        _ = budget.store(21, bytes: 1, protecting: [1])
        XCTAssertTrue(budget.contains(1))
        XCTAssertFalse(budget.contains(2))
        XCTAssertTrue(budget.contains(21))
        XCTAssertEqual(budget.count, 20)
    }

    /// `evict(protecting: [])` drops down to the cap after a protecting store overfilled it.
    func testEvictIdleDropsDownToCapWithEmptyProtecting() {
        let budget = ThumbnailBudget()
        let protecting = Set((1...25).map { CGWindowID($0) })
        store(budget, 1...25, bytes: 1, protecting: protecting)
        XCTAssertEqual(budget.count, 25)
        let evicted = budget.evict(protecting: [])
        XCTAssertEqual(Set(evicted), Set((1...5).map { CGWindowID($0) }))
        XCTAssertEqual(budget.count, 20)
        XCTAssertFalse(budget.contains(1))
        XCTAssertFalse(budget.contains(5))
        XCTAssertTrue(budget.contains(6))
        XCTAssertTrue(budget.contains(25))
    }
}
