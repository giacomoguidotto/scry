import AppKit

/// Bundles all outputs from the extraction pipeline.
struct ExtractionResult {
    /// Screenshot annotated with cursor indicator (for LLM).
    let screenshot: CGImage?
    /// Raw screenshot without cursor ring (for OCR — ring would confuse Vision).
    let rawScreenshot: CGImage?
    /// Cursor position in NSScreen coordinates.
    let cursorPosition: NSPoint
    /// Full selected text from Accessibility API (may include off-screen content).
    let axText: String?
    /// Full OCR text from the screenshot.
    let ocrText: String?
    /// OCR line nearest the cursor center.
    let ocrCenterLine: String?

    /// Best available text for web search providers.
    var queryText: String {
        if let ax = axText, !ax.isEmpty {
            return ax.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let center = ocrCenterLine, !center.isEmpty {
            return center.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let ocr = ocrText, !ocr.isEmpty {
            return ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}

/// Controls what area is captured in screenshots.
enum ScreenshotMode: String, Codable, CaseIterable {
    /// Square region around cursor (configurable size).
    case region
    /// Focused app window (default — captures what the user is looking at).
    case window
    /// Full display.
    case screen

    var displayName: String {
        switch self {
        case .region: return "Region around cursor"
        case .window: return "Focused window"
        case .screen: return "Full screen"
        }
    }
}
