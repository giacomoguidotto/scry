import AppKit
import Combine
import XCTest
@testable import Scry

final class PressureRoutingTests: XCTestCase {
    func testTapMaskIncludesQuartzGestureEnvelopeAndDirectPressure() {
        XCTAssertNotEqual(EventTapService.eventMask & (1 << 29), 0)
        XCTAssertNotEqual(EventTapService.eventMask & (1 << 34), 0)
    }

    func testQuartzGestureEnvelopeDecodedAsPressureTriggersOnceAtStageTwo() {
        var stage = 1
        let service = EventTapService(pressureEventReader: { _ in
            .init(type: .pressure, stage: stage, pressure: 1)
        })
        let event = CGEvent(source: nil)!
        let delivered = expectation(description: "Force click delivered")
        delivered.assertForOverFulfill = true
        var received: [ForceClickEvent] = []
        var snapshotID: UUID?
        let snapshot = service.mouseDownPublisher.sink { snapshotID = $0 }
        let lookup = service.forceClickPublisher.sink {
            received.append($0)
            delivered.fulfill()
        }
        service.handleMouseEvent(type: .leftMouseDown, location: event.location)

        XCTAssertFalse(service.handleGestureEvent(type: EventTapService.gestureEventType, event: event))
        XCTAssertTrue(received.isEmpty, "Stage one at full pressure is an ordinary click")
        stage = 2
        XCTAssertTrue(service.handleGestureEvent(type: EventTapService.gestureEventType, event: event))
        XCTAssertTrue(service.handleGestureEvent(type: EventTapService.pressureEventType, event: event))
        wait(for: [delivered], timeout: 1)

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.gestureID, snapshotID)
        withExtendedLifetime((snapshot, lookup)) {}
    }

    func testOtherQuartzGesturesPassThroughEvenIfReaderReportsStageTwo() {
        let service = EventTapService(pressureEventReader: { _ in
            .init(type: .magnify, stage: 2, pressure: 1)
        })
        let event = CGEvent(source: nil)!
        service.handleMouseEvent(type: .leftMouseDown, location: event.location)

        XCTAssertFalse(service.handleGestureEvent(type: EventTapService.gestureEventType, event: event))
    }

    func testOrdinaryMousePressureDoesNotEnterGestureDecoder() {
        var decodes = 0
        let service = EventTapService(pressureEventReader: { _ in
            decodes += 1
            return .init(type: .pressure, stage: 2, pressure: 1)
        })
        let event = CGEvent(source: nil)!
        event.setDoubleValueField(.mouseEventPressure, value: 1)
        service.handleMouseEvent(type: .leftMouseDown, location: event.location)

        XCTAssertFalse(service.handleGestureEvent(type: .leftMouseDragged, event: event))
        XCTAssertEqual(decodes, 0)
    }

    func testUndecodableGesturePassesThroughWithoutLookup() {
        let service = EventTapService(pressureEventReader: { _ in nil })
        let event = CGEvent(source: nil)!
        service.handleMouseEvent(type: .leftMouseDown, location: event.location)

        XCTAssertFalse(service.handleGestureEvent(type: EventTapService.gestureEventType, event: event))
    }
}
