import AppKit
import XCTest
@testable import Scry

final class ForceClickDetectorTests: XCTestCase {
    func testOrdinaryHoldNeverFiresRegardlessOfDuration() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        fixture.time = 60
        fixture.detector.mouseDragged(to: .zero)
        fixture.detector.mouseUp()

        XCTAssertTrue(fixture.events.isEmpty)
    }

    func testStageOneHoldNeverFiresWithPressureUpdatesOrSmallDrags() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        for time in [0.1, 0.3, 1, 10, 60] {
            fixture.time = time
            XCTAssertFalse(fixture.detector.pressureChanged(to: 1, at: .zero))
            fixture.detector.mouseDragged(to: CGPoint(x: 1, y: 1))
        }
        fixture.detector.mouseUp()

        XCTAssertTrue(fixture.events.isEmpty)
    }

    func testPressureAfterReleaseIsForwardedWithoutLookup() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        fixture.detector.mouseUp()

        XCTAssertFalse(fixture.detector.pressureChanged(to: 2, at: .zero))
        XCTAssertTrue(fixture.events.isEmpty)
    }

    func testDriftPermanentlyRejectsPressEvenAfterCursorReturns() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        fixture.detector.mouseDragged(to: CGPoint(x: 5, y: 0))
        fixture.detector.mouseDragged(to: .zero)

        XCTAssertTrue(fixture.events.isEmpty)
        XCTAssertFalse(fixture.detector.pressureChanged(to: 2, at: .zero))
    }

    func testPressureChecksCurrentCursorDriftWithoutDragDelivery() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        XCTAssertFalse(fixture.detector.pressureChanged(to: 2, at: CGPoint(x: 0, y: 5)))

        XCTAssertTrue(fixture.events.isEmpty)
    }

    func testRealStageTwoTriggersImmediatelyWithOriginalSnapshot() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        fixture.time = 0.01

        XCTAssertTrue(fixture.detector.pressureChanged(to: 2, at: .zero))
        XCTAssertEqual(fixture.events.count, 1)
        XCTAssertEqual(fixture.events.first?.gestureID, fixture.snapshots.first)
    }

    func testRepeatedPressureTransitionsNeverRefireSamePress() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        XCTAssertTrue(fixture.detector.pressureChanged(to: 2, at: .zero))
        fixture.time = 1
        XCTAssertFalse(fixture.detector.pressureChanged(to: 1, at: .zero))
        XCTAssertTrue(fixture.detector.pressureChanged(to: 2, at: .zero))

        XCTAssertEqual(fixture.events.count, 1)
    }

    func testNewPressResetsStageEvenWhenStageZeroWasNotDelivered() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        XCTAssertTrue(fixture.detector.pressureChanged(to: 2, at: .zero))
        fixture.detector.mouseUp()
        fixture.time = 1
        fixture.detector.mouseDown(at: .zero)

        XCTAssertTrue(fixture.detector.pressureChanged(to: 2, at: .zero))
        XCTAssertEqual(fixture.events.count, 2)
        XCTAssertNotEqual(fixture.events[0].gestureID, fixture.events[1].gestureID)
    }

    func testLongHoldFiresOnlyWhenStageTwoArrives() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)

        fixture.time = 60
        fixture.detector.mouseDragged(to: .zero)
        XCTAssertTrue(fixture.events.isEmpty)
        XCTAssertTrue(fixture.detector.pressureChanged(to: 2, at: .zero))
        XCTAssertEqual(fixture.events.count, 1)
    }

    func testRejectedPressureIsForwardedWithoutLookup() {
        let fixture = Fixture()
        XCTAssertFalse(fixture.detector.pressureChanged(to: 2, at: .zero))
        fixture.detector.mouseDown(at: .zero)

        XCTAssertFalse(fixture.detector.pressureChanged(to: 2, at: CGPoint(x: 5, y: 0)))
        XCTAssertTrue(fixture.events.isEmpty)
    }

    func testDebouncedSecondPressIsForwardedWithoutLookup() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        XCTAssertTrue(fixture.detector.pressureChanged(to: 2, at: .zero))
        fixture.detector.mouseUp()
        fixture.time = 0.01
        fixture.detector.mouseDown(at: .zero)

        XCTAssertFalse(fixture.detector.pressureChanged(to: 2, at: .zero))
        XCTAssertEqual(fixture.events.count, 1)
    }

    func testStageZeroOneAndUnknownStagesNeverFire() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        for stage in [0, 1, 3, -1] {
            XCTAssertFalse(fixture.detector.pressureChanged(to: stage, at: .zero))
        }
        XCTAssertTrue(fixture.events.isEmpty)
    }

    func testStopOrTapRecoveryCancelsPendingGesture() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        fixture.detector.cancel()

        XCTAssertTrue(fixture.events.isEmpty)
        XCTAssertFalse(fixture.detector.pressureChanged(to: 2, at: .zero))
    }

    func testPassiveDuplicatePreservesSnapshotAndCannotTriggerLookup() {
        let fixture = Fixture()
        fixture.detector.mouseDown(at: .zero)
        fixture.time = 0.1
        fixture.detector.mouseDown(at: .zero, passive: true)

        XCTAssertEqual(fixture.snapshots.count, 1)
        XCTAssertTrue(fixture.events.isEmpty)
        XCTAssertTrue(fixture.detector.pressureChanged(to: 2, at: .zero))
        XCTAssertEqual(fixture.events.first?.gestureID, fixture.snapshots.first)
    }

    private final class Fixture {
        var time: TimeInterval = 0
        var snapshots: [UUID] = []
        var events: [ForceClickEvent] = []

        lazy var detector = ForceClickDetector(
            now: { [unowned self] in time },
            onMouseDown: { [unowned self] in snapshots.append($0) },
            onForceClick: { [unowned self] in events.append($0) }
        )
    }
}
