import AppKit
import CoreGraphics

final class ScreenshotService {
    private let debugLog = DebugLogStore.shared

    // MARK: - Unified Capture

    /// Captures a screenshot and returns both annotated (with cursor ring) and raw versions.
    func capture(
        mode: ScreenshotMode,
        around point: NSPoint,
        frontApp: NSRunningApplication?
    ) -> (annotated: CGImage, raw: CGImage)? {
        let raw: CGImage?
        switch mode {
        case .region:
            raw = captureRegion(around: point, size: AppSettings.shared.screenshotRegionSize)
        case .window:
            raw = captureWindow(of: frontApp) ?? captureRegion(around: point, size: 800)
        case .screen:
            raw = captureScreen(containing: point)
        }

        guard var image = raw else { return nil }

        // Downscale if needed
        image = downscale(image, maxEdge: Constants.Screenshot.maxImageEdge)

        // Annotate with cursor indicator for LLM
        let annotated = annotateWithCursor(image, cursorScreenPoint: point, frontApp: frontApp, mode: mode)

        return (annotated: annotated ?? image, raw: image)
    }

    // MARK: - Region Capture

    func captureRegion(around point: NSPoint, size: CGFloat) -> CGImage? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
                ?? NSScreen.main else {
            debugLog.log("Screenshot", "No screen found for point", level: .warning)
            return nil
        }

        let screenHeight = screen.frame.height + screen.frame.origin.y
        let cgY = screenHeight - point.y
        let half = size / 2
        let rect = CGRect(x: point.x - half, y: cgY - half, width: size, height: size)

        let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
        if image == nil {
            debugLog.log("Screenshot", "Region capture returned nil", level: .warning)
        }
        return image
    }

    // MARK: - Window Capture

    private func captureWindow(of app: NSRunningApplication?) -> CGImage? {
        guard let app = app else { return nil }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[CFString: Any]] ?? []

        // Find the frontmost on-screen window for this app (layer 0 = normal windows)
        let appWindows = windowList.filter { info in
            let pid = info[kCGWindowOwnerPID] as? pid_t
            let layer = info[kCGWindowLayer] as? Int
            let alpha = info[kCGWindowAlpha] as? Double
            return pid == app.processIdentifier && layer == 0 && (alpha ?? 1.0) > 0
        }

        guard let windowInfo = appWindows.first,
              let windowID = windowInfo[kCGWindowNumber] as? CGWindowID else {
            debugLog.log("Screenshot", "No window found for \(app.bundleIdentifier ?? "?")", level: .debug)
            return nil
        }

        let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .bestResolution)
        if let image = image {
            debugLog.log("Screenshot", "Window capture \(image.width)x\(image.height)", level: .debug)
        }
        return image
    }

    // MARK: - Screen Capture

    private func captureScreen(containing point: NSPoint) -> CGImage? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
                ?? NSScreen.main else { return nil }

        let screenHeight = screen.frame.height + screen.frame.origin.y
        let rect = CGRect(
            x: screen.frame.origin.x,
            y: screenHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )

        let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
        if let image = image {
            debugLog.log("Screenshot", "Screen capture \(image.width)x\(image.height)", level: .debug)
        }
        return image
    }

    // MARK: - Downscale

    private func downscale(_ image: CGImage, maxEdge: Int) -> CGImage {
        let w = image.width
        let h = image.height
        guard max(w, h) > maxEdge else { return image }

        let scale = Double(maxEdge) / Double(max(w, h))
        let newW = Int(Double(w) * scale)
        let newH = Int(Double(h) * scale)

        guard let context = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))

        let result = context.makeImage()
        if let result = result {
            debugLog.log("Screenshot", "Downscaled \(w)x\(h) → \(newW)x\(newH)", level: .debug)
            return result
        }
        return image
    }

    // MARK: - Cursor Annotation

    private func annotateWithCursor(
        _ image: CGImage,
        cursorScreenPoint: NSPoint,
        frontApp: NSRunningApplication?,
        mode: ScreenshotMode
    ) -> CGImage? {
        // Calculate cursor position relative to the image
        let imgW = image.width
        let imgH = image.height
        let relativePoint: CGPoint

        switch mode {
        case .region:
            // Cursor is at center of the region
            relativePoint = CGPoint(x: CGFloat(imgW) / 2, y: CGFloat(imgH) / 2)

        case .window:
            // Find window bounds to compute relative position
            guard let app = frontApp else { return nil }
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[CFString: Any]] ?? []
            guard let windowInfo = windowList.first(where: {
                ($0[kCGWindowOwnerPID] as? pid_t) == app.processIdentifier
                    && ($0[kCGWindowLayer] as? Int) == 0
            }),
                  let boundsDict = windowInfo[kCGWindowBounds] as? [String: CGFloat],
                  let winX = boundsDict["X"], let winY = boundsDict["Y"],
                  let winW = boundsDict["Width"], let winH = boundsDict["Height"] else { return nil }

            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorScreenPoint) })
                    ?? NSScreen.main else { return nil }
            let screenHeight = screen.frame.height + screen.frame.origin.y
            let cgCursorY = screenHeight - cursorScreenPoint.y

            let relX = (cursorScreenPoint.x - winX) / winW * CGFloat(imgW)
            let relY = (cgCursorY - winY) / winH * CGFloat(imgH)
            relativePoint = CGPoint(x: relX, y: relY)

        case .screen:
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorScreenPoint) })
                    ?? NSScreen.main else { return nil }
            let screenHeight = screen.frame.height + screen.frame.origin.y
            let relX = (cursorScreenPoint.x - screen.frame.origin.x) / screen.frame.width * CGFloat(imgW)
            let relY = (screenHeight - cursorScreenPoint.y - (screenHeight - screen.frame.maxY))
                / screen.frame.height * CGFloat(imgH)
            relativePoint = CGPoint(x: relX, y: relY)
        }

        // Draw a subtle accent-colored ring
        guard let context = CGContext(
            data: nil,
            width: imgW,
            height: imgH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Draw original image
        context.draw(image, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))

        // Draw cursor ring (accent color: #5DE4C7)
        let radius: CGFloat = min(CGFloat(min(imgW, imgH)) * 0.02, 20)
        let lineWidth: CGFloat = max(radius * 0.3, 2)
        let center = CGPoint(x: relativePoint.x, y: CGFloat(imgH) - relativePoint.y)

        context.setStrokeColor(CGColor(red: 0x5D / 255.0, green: 0xE4 / 255.0, blue: 0xC7 / 255.0, alpha: 0.9))
        context.setLineWidth(lineWidth)
        context.addEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.strokePath()

        return context.makeImage()
    }
}
