import AppKit
import Combine
import XCTest
@testable import Scry

final class SelectionCaptureTests: XCTestCase {
    func testSnapshotSurvivesSelectionCollapsingAndIsConsumedOnce() {
        var selection: String? = "selected word"
        let extractor = TextExtractorService(selectedTextReader: { _, _ in selection })
        let gestureID = UUID()
        extractor.snapshotSelection(processIdentifier: 101, gestureID: gestureID)
        selection = nil

        XCTAssertEqual(extractor.selectedText(processIdentifier: 101, gestureID: gestureID), "selected word")
        XCTAssertNil(extractor.selectedText(processIdentifier: 101, gestureID: gestureID))
    }

    func testNilSnapshotClearsEarlierSelection() {
        var selection: String? = "earlier word"
        let extractor = TextExtractorService(selectedTextReader: { _, _ in selection })
        let earlierGesture = UUID()
        extractor.snapshotSelection(processIdentifier: 101, gestureID: earlierGesture)
        selection = nil
        extractor.snapshotSelection(processIdentifier: 101, gestureID: UUID())

        XCTAssertNil(extractor.selectedText(processIdentifier: 101, gestureID: earlierGesture))
    }

    func testEmptySnapshotClearsEarlierSelection() {
        var selection: String? = "earlier word"
        let extractor = TextExtractorService(selectedTextReader: { _, _ in selection })
        let earlierGesture = UUID()
        extractor.snapshotSelection(processIdentifier: 101, gestureID: earlierGesture)
        selection = ""
        extractor.snapshotSelection(processIdentifier: 101, gestureID: UUID())
        selection = nil

        XCTAssertNil(extractor.selectedText(processIdentifier: 101, gestureID: earlierGesture))
    }

    func testMissingApplicationClearsEarlierSnapshot() {
        var selection: String? = "earlier word"
        let extractor = TextExtractorService(selectedTextReader: { _, _ in selection })
        let earlierGesture = UUID()
        extractor.snapshotSelection(processIdentifier: 101, gestureID: earlierGesture)
        extractor.snapshotSelection(processIdentifier: nil, gestureID: UUID())
        selection = nil

        XCTAssertNil(extractor.selectedText(processIdentifier: 101, gestureID: earlierGesture))
    }

    func testKeyboardReadsLiveSelectionInsteadOfMouseSnapshot() {
        var selection: String? = "mouse word"
        let extractor = TextExtractorService(selectedTextReader: { _, _ in selection })
        let gestureID = UUID()
        extractor.snapshotSelection(processIdentifier: 101, gestureID: gestureID)
        selection = "keyboard word"

        XCTAssertEqual(extractor.selectedText(processIdentifier: 101), "keyboard word")
        selection = nil
        XCTAssertNil(extractor.selectedText(processIdentifier: 101, gestureID: gestureID))
    }

    func testDifferentApplicationCannotConsumeSnapshot() {
        var selection: String? = "application one"
        let extractor = TextExtractorService(selectedTextReader: { _, _ in selection })
        let gestureID = UUID()
        extractor.snapshotSelection(processIdentifier: 101, gestureID: gestureID)
        selection = "application two"

        XCTAssertEqual(extractor.selectedText(processIdentifier: 202, gestureID: gestureID), "application two")
        selection = nil
        XCTAssertNil(extractor.selectedText(processIdentifier: 101, gestureID: gestureID))
    }

    func testDifferentGestureCannotConsumeSnapshot() {
        var selection: String? = "previous press"
        let extractor = TextExtractorService(selectedTextReader: { _, _ in selection })
        extractor.snapshotSelection(processIdentifier: 101, gestureID: UUID())
        selection = "current selection"

        XCTAssertEqual(extractor.selectedText(processIdentifier: 101, gestureID: UUID()), "current selection")
    }

    func testMouseDownCapturesSynchronouslyBeforeClickCollapsesSelection() {
        let eventTap = EventTapService()
        var selection: String? = "selected before click"
        let extractor = TextExtractorService(selectedTextReader: { _, _ in selection })
        var capturedGesture: UUID?
        let subscription = eventTap.mouseDownPublisher.sink { gestureID in
            capturedGesture = gestureID
            extractor.snapshotSelection(processIdentifier: 101, gestureID: gestureID)
        }

        eventTap.handleMouseEvent(type: .leftMouseDown, location: .zero)
        XCTAssertNotNil(capturedGesture, "Selection must be captured before the event callback returns")
        selection = nil // The target application receives the original click now.
        XCTAssertEqual(extractor.selectedText(processIdentifier: 101, gestureID: capturedGesture), "selected before click")
        withExtendedLifetime(subscription) {}
    }

    func testPassiveDeliveryDoesNotOverwriteEarlyActiveCapture() {
        let eventTap = EventTapService()
        var deliveries = 0
        let subscription = eventTap.mouseDownPublisher.sink { _ in deliveries += 1 }

        eventTap.handleMouseEvent(type: .leftMouseDown, location: .zero)
        eventTap.handlePassiveMouseDown(location: .zero)

        XCTAssertEqual(deliveries, 1)
        eventTap.handleMouseEvent(type: .leftMouseUp, location: .zero)
        eventTap.handlePassiveMouseDown(location: .zero)
        XCTAssertEqual(deliveries, 2, "Fallback must still capture when the active tap did not")
        withExtendedLifetime(subscription) {}
    }

    func testMouseDownBoundsAXReadsAndKeyboardUsesNormalTimeout() {
        var timeouts: [Float?] = []
        let extractor = TextExtractorService(selectedTextReader: { _, timeout in
            timeouts.append(timeout)
            return nil
        })
        extractor.snapshotSelection(processIdentifier: 101, gestureID: UUID())
        _ = extractor.selectedText(processIdentifier: 101)

        XCTAssertEqual(timeouts.count, 2)
        XCTAssertEqual(timeouts[0], 0.03)
        XCTAssertNil(timeouts[1])
    }
}
