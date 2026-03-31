import AppKit
import ApplicationServices
import NaturalLanguage

final class TextExtractorService {
    private let debugLog = DebugLogStore.shared
    private let screenshotService = ScreenshotService()
    private let ocrService = OCRService()

    /// Selection snapshot taken at mouse-down, before force-click auto-selects text.
    private var preGestureSelection: String?

    /// Snapshots the current selection at mouse-down time (before force-click
    /// auto-selects text). Called on every mouse-down while the event tap is active.
    func snapshotSelection() {
        if let text = extractViaAccessibility(), !text.isEmpty {
            preGestureSelection = text
            debugLog.log("TextExtractor", "Snapshot: got selection via AX", level: .debug)
            return
        }
    }

    /// LLM-first extraction pipeline: screenshot first, text second.
    func extract(at point: NSPoint, frontApp: NSRunningApplication? = nil) async -> ExtractionResult {
        let cursorPoint = point

        // 1. Capture screenshot (always, unconditionally)
        let mode = AppSettings.shared.screenshotMode
        let captured = screenshotService.capture(mode: mode, around: cursorPoint, frontApp: frontApp)

        // 2. AX text extraction (best-effort)
        var axText = preGestureSelection
        preGestureSelection = nil
        if axText == nil {
            axText = extractViaAccessibility(frontApp: frontApp)
        }
        if let text = axText, !text.isEmpty {
            debugLog.log("TextExtractor", "AX: got \"\(text.prefix(80))\"", level: .debug)
        }

        // 3. OCR on the raw screenshot (no cursor ring — would confuse Vision)
        var ocrText: String?
        var ocrCenterLine: String?
        if let raw = captured?.raw {
            if let result = await ocrService.recognizeText(in: raw) {
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

    private func extractViaAccessibility(frontApp: NSRunningApplication? = nil) -> String? {
        let app = frontApp ?? NSWorkspace.shared.frontmostApplication
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

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedValue: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard focusResult == .success else {
            debugLog.log("TextExtractor", "AX: no focused element (\(focusResult.rawValue))", level: .debug)
            return nil
        }

        // swiftlint:disable:next force_cast
        let focusedElement = focusedValue as! AXUIElement

        var selectedTextValue: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            focusedElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        guard textResult == .success, let text = selectedTextValue as? String, !text.isEmpty else {
            debugLog.log("TextExtractor", "AX: no selected text (\(textResult.rawValue))", level: .debug)
            return nil
        }

        return text
    }
}
