import AppKit
import ApplicationServices
import NaturalLanguage

final class TextExtractorService {
    private let debugLog = DebugLogStore.shared
    private let captureScreenshot: (ScreenshotMode, NSPoint, NSRunningApplication?) -> (annotated: CGImage, raw: CGImage)?
    private let recognizeText: (CGImage) async -> OCRResult?

    private struct SelectionSnapshot {
        let processIdentifier: pid_t
        let gestureID: UUID
        let text: String
    }

    private let selectionLock = NSLock()
    private var preGestureSelection: SelectionSnapshot?
    private let selectedTextReader: (pid_t, Float?) -> String?

    init(
        captureScreenshot: @escaping (ScreenshotMode, NSPoint, NSRunningApplication?) -> (annotated: CGImage, raw: CGImage)?
            = ScreenshotService().capture,
        recognizeText: @escaping (CGImage) async -> OCRResult? = OCRService().recognizeText,
        selectedTextReader: @escaping (pid_t, Float?) -> String? = TextExtractorService.readSelectedText
    ) {
        self.captureScreenshot = captureScreenshot
        self.recognizeText = recognizeText
        self.selectedTextReader = selectedTextReader
    }

    /// Snapshots the current selection at mouse-down time (before force-click
    /// auto-selects text). Called on every mouse-down while the event tap is active.
    func snapshotSelection(gestureID: UUID) {
        snapshotSelection(processIdentifier: externalProcessIdentifier(NSWorkspace.shared.frontmostApplication), gestureID: gestureID)
    }

    func snapshotSelection(processIdentifier: pid_t?, gestureID: UUID) {
        // Two AX calls are bounded to 30ms each so an unresponsive application
        // cannot stall the synchronous event tap callback for the default AX timeout.
        let text = processIdentifier.flatMap { selectedTextReader($0, 0.03) }
        selectionLock.lock()
        defer { selectionLock.unlock() }
        preGestureSelection = nil
        if let processIdentifier = processIdentifier, let text = text, !text.isEmpty {
            preGestureSelection = SelectionSnapshot(processIdentifier: processIdentifier, gestureID: gestureID, text: text)
        }
    }

    /// Keyboard shortcuts always read the current selection. A force-click can
    /// consume only its own application's snapshot, exactly once.
    func selectedText(processIdentifier: pid_t?, gestureID: UUID? = nil) -> String? {
        selectionLock.lock()
        let snapshot = preGestureSelection
        preGestureSelection = nil
        selectionLock.unlock()
        guard let processIdentifier = processIdentifier else { return nil }
        if let gestureID = gestureID, snapshot?.gestureID == gestureID,
           snapshot?.processIdentifier == processIdentifier {
            return snapshot?.text
        }
        return selectedTextReader(processIdentifier, nil)
    }

    /// LLM-first extraction pipeline, retaining both screenshot and selected text.
    func extract(at point: NSPoint, frontApp: NSRunningApplication? = nil, gestureID: UUID? = nil) async -> ExtractionResult {
        await extract(
            at: point,
            processIdentifier: externalProcessIdentifier(frontApp ?? NSWorkspace.shared.frontmostApplication),
            frontApp: frontApp,
            gestureID: gestureID
        )
    }

    func extract(
        at point: NSPoint,
        processIdentifier: pid_t?,
        frontApp: NSRunningApplication? = nil,
        gestureID: UUID? = nil
    ) async -> ExtractionResult {
        let cursorPoint = point

        // Read AX before screenshot work; keyboard selection must be current.
        let axText = selectedText(
            processIdentifier: processIdentifier,
            gestureID: gestureID
        )

        // Capture screenshot (always, unconditionally)
        let mode = AppSettings.shared.screenshotMode
        let captured = captureScreenshot(mode, cursorPoint, frontApp)

        if let text = axText, !text.isEmpty {
            debugLog.log("TextExtractor", "AX: got \"\(text.prefix(80))\"", level: .debug)
        }

        // A selected phrase already supplies the query; retain the screenshots for
        // vision-capable providers without starting redundant on-device OCR.
        var ocrText: String?
        var ocrCenterLine: String?
        if axText?.isEmpty != false, let raw = captured?.raw {
            if let result = await recognizeText(raw) {
                ocrText = result.fullText
                ocrCenterLine = result.lineNearestCenter
                if let line = ocrCenterLine {
                    debugLog.log("TextExtractor", "OCR center: \"\(line.prefix(80))\"", level: .debug)
                }
            }
        }

        return ExtractionResult(
            screenshot: captured?.annotated,
            rawScreenshot: captured?.raw,
            cursorPosition: cursorPoint,
            axText: axText,
            ocrText: ocrText,
            ocrCenterLine: ocrCenterLine
        )
    }

    // MARK: - Accessibility

    private func externalProcessIdentifier(_ app: NSRunningApplication?) -> pid_t? {
        guard let app = app else {
            debugLog.log("TextExtractor", "AX: no frontmost app", level: .debug)
            return nil
        }

        let bundleID = app.bundleIdentifier ?? "unknown"
        debugLog.log("TextExtractor", "AX: app = \(bundleID)", level: .debug)

        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            debugLog.log("TextExtractor", "AX: frontmost is Scry, skipping", level: .debug)
            return nil
        }

        return app.processIdentifier
    }

    private static func readSelectedText(processIdentifier: pid_t, timeout: Float?) -> String? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        if let timeout = timeout {
            guard AXUIElementSetMessagingTimeout(appElement, timeout) == .success else { return nil }
        }

        var focusedValue: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard focusResult == .success else {
            return nil
        }

        // swiftlint:disable:next force_cast
        let focusedElement = focusedValue as! AXUIElement
        // Apple specifies that this timeout applies only to the individual object.
        if let timeout = timeout {
            guard AXUIElementSetMessagingTimeout(focusedElement, timeout) == .success else { return nil }
        }

        var selectedTextValue: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            focusedElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        guard textResult == .success, let text = selectedTextValue as? String, !text.isEmpty else {
            return nil
        }

        return text
    }
}
