import Cocoa
import XCTest

final class SwitcherSessionTests: XCTestCase {
    private let tenMiB: UInt64 = 10 * 1024 * 1024

    private func stub(_ bytes: UInt64) -> CALayerContents { .stub(byteSize: bytes) }

    private func store(_ session: SwitcherSession, _ ids: ClosedRange<Int>, bytes: UInt64) {
        for id in ids {
            session.storePreviewFrame(CGWindowID(id), stub(bytes))
        }
    }

    /// The 11th stored frame drops the least recently used id; the other ten remain.
    func testCountEvictionDropsTheLeastRecentlyStoredFrame() {
        let session = SwitcherSession()
        store(session, 1...11, bytes: 1)
        XCTAssertFalse(session.hasPreviewFrame(1))
        for id in 2...11 {
            XCTAssertTrue(session.hasPreviewFrame(CGWindowID(id)), "expected \(id) cached")
        }
    }

    /// Frames whose bytes exceed 64 MiB drop least recently used ids until the remainder fits.
    func testByteBudgetEvictsLeastRecentlyUsedFrames() {
        let session = SwitcherSession()
        store(session, 1...7, bytes: tenMiB)
        XCTAssertFalse(session.hasPreviewFrame(1))
        for id in 2...7 {
            XCTAssertTrue(session.hasPreviewFrame(CGWindowID(id)), "expected \(id) cached")
        }
    }

    /// Storing a smaller frame for an existing id frees the old bytes so a later frame can fit.
    func testReplacingAFrameReleasesItsOldBytes() {
        let session = SwitcherSession()
        store(session, 1...6, bytes: tenMiB)
        session.storePreviewFrame(6, stub(20 * 1024 * 1024))
        XCTAssertFalse(session.hasPreviewFrame(1))
        for id in 2...6 {
            XCTAssertTrue(session.hasPreviewFrame(CGWindowID(id)), "expected \(id) cached")
        }
    }

    /// `previewFrame` promotes that id so a later store evicts a different least-recently-used id.
    func testReadingAFrameProtectsItFromCountEviction() {
        let session = SwitcherSession()
        store(session, 1...10, bytes: 1)
        XCTAssertNotNil(session.previewFrame(1))
        session.storePreviewFrame(11, stub(1))
        XCTAssertTrue(session.hasPreviewFrame(1))
        XCTAssertFalse(session.hasPreviewFrame(2))
        XCTAssertTrue(session.hasPreviewFrame(11))
    }

    /// A frame larger than 64 MiB evicts every older id and remains readable.
    func testOversizedNewestFrameIsRetainedAlone() {
        let session = SwitcherSession()
        store(session, 1...3, bytes: tenMiB)
        session.storePreviewFrame(4, stub(70 * 1024 * 1024))
        XCTAssertFalse(session.hasPreviewFrame(1))
        XCTAssertFalse(session.hasPreviewFrame(2))
        XCTAssertFalse(session.hasPreviewFrame(3))
        XCTAssertTrue(session.hasPreviewFrame(4))
        guard case .stub(let bytes) = session.previewFrame(4) else {
            return XCTFail("expected the oversized frame to remain readable")
        }
        XCTAssertEqual(bytes, 70 * 1024 * 1024)
    }

    // MARK: - pinned selected frame (`pinnedPreviewWid`)

    /// Regression: neighbor prefetch blew the 64 MiB budget and plain LRU evicted the selected window's
    /// frame first. The pinned frame must survive while its neighbors pay for the budget, LRU-first.
    func testPinnedSelectedFrameSurvivesByteBudgetEviction() {
        let session = SwitcherSession()
        session.pinnedPreviewWid = 1
        store(session, 1...7, bytes: tenMiB)
        XCTAssertTrue(
            session.hasPreviewFrame(1),
            "the displayed preview must survive neighbor prefetch eviction")
        XCTAssertFalse(
            session.hasPreviewFrame(2), "the neighbor stored right after the pin is the LRU victim")
        for id in 3...7 {
            XCTAssertTrue(session.hasPreviewFrame(CGWindowID(id)), "expected \(id) cached")
        }
    }

    /// Moving the selection moves the pin: the previously pinned frame becomes evictable again.
    func testMovingThePinReleasesTheOldFrame() {
        let session = SwitcherSession()
        session.pinnedPreviewWid = 1
        store(session, 1...7, bytes: tenMiB)
        XCTAssertFalse(session.hasPreviewFrame(2))
        session.pinnedPreviewWid = 7
        session.storePreviewFrame(8, stub(tenMiB))
        XCTAssertFalse(
            session.hasPreviewFrame(1),
            "the frame of the window that is no longer selected is evictable")
        XCTAssertTrue(session.hasPreviewFrame(7), "the newly selected window's frame is now pinned")
        XCTAssertTrue(session.hasPreviewFrame(8))
    }

    /// An oversized PINNED frame is retained even though it alone exceeds 64 MiB, and later neighbor
    /// stores are evicted instead of it: it is the one on screen.
    func testOversizedPinnedFrameIsRetainedAlone() {
        let session = SwitcherSession()
        session.pinnedPreviewWid = 1
        session.storePreviewFrame(1, stub(70 * 1024 * 1024))
        store(session, 2...4, bytes: tenMiB)
        XCTAssertTrue(
            session.hasPreviewFrame(1), "the oversized frame the user is looking at must display")
        for id in 2...4 {
            XCTAssertFalse(session.hasPreviewFrame(CGWindowID(id)))
        }
        guard case .stub(let bytes) = session.previewFrame(1) else {
            return XCTFail("expected the oversized pinned frame to remain readable")
        }
        XCTAssertEqual(bytes, 70 * 1024 * 1024)
    }

    /// The count cap keeps evicting around the pin: only the pinned id is exempt, not the eviction itself.
    func testCountCapStillEvictsAroundThePin() {
        let session = SwitcherSession()
        session.pinnedPreviewWid = 5
        store(session, 1...11, bytes: 1)
        XCTAssertFalse(
            session.hasPreviewFrame(1),
            "the count cap still evicts the least recently used neighbor")
        XCTAssertTrue(session.hasPreviewFrame(5), "the pinned id survives the count cap")
        XCTAssertTrue(session.hasPreviewFrame(11))
    }
}
