import AppKit
import XCTest
@testable import Scry

final class TextExtractionPipelineTests: XCTestCase {
    func testCapturedSelectionSkipsOCRAndPreservesBothScreenshots() async throws {
        let raw = try makeImage(width: 2)
        let annotated = try makeImage(width: 3)
        var selection: String? = "selected phrase"
        var captures = 0
        var recognitions = 0
        let service = TextExtractorService(
            captureScreenshot: { _, point, _ in
                captures += 1
                XCTAssertEqual(point, NSPoint(x: 20, y: 30))
                return (annotated, raw)
            },
            recognizeText: { _ in
                recognitions += 1
                return OCRResult(fullText: "redundant OCR", lineNearestCenter: "redundant OCR")
            },
            selectedTextReader: { _, _ in selection }
        )
        let gestureID = UUID()
        service.snapshotSelection(processIdentifier: 101, gestureID: gestureID)
        selection = nil

        let result = await service.extract(at: NSPoint(x: 20, y: 30), processIdentifier: 101, gestureID: gestureID)

        XCTAssertEqual(result.axText, "selected phrase")
        XCTAssertEqual(result.queryText, "selected phrase")
        XCTAssertTrue(result.rawScreenshot === raw)
        XCTAssertTrue(result.screenshot === annotated)
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(recognitions, 0)
        XCTAssertNil(result.ocrText)
        XCTAssertNil(result.ocrCenterLine)
    }

    func testScreenshotOnlyLookupRunsOCROnRawImage() async throws {
        let raw = try makeImage(width: 2)
        let annotated = try makeImage(width: 3)
        var recognitions = 0
        let service = TextExtractorService(
            captureScreenshot: { _, _, _ in (annotated, raw) },
            recognizeText: { image in
                recognitions += 1
                XCTAssertTrue(image === raw)
                return OCRResult(fullText: "screen text", lineNearestCenter: "cursor line")
            },
            selectedTextReader: { _, _ in nil }
        )

        let result = await service.extract(at: .zero, processIdentifier: 101)

        XCTAssertNil(result.axText)
        XCTAssertEqual(result.ocrText, "screen text")
        XCTAssertEqual(result.ocrCenterLine, "cursor line")
        XCTAssertEqual(result.queryText, "cursor line")
        XCTAssertTrue(result.rawScreenshot === raw)
        XCTAssertTrue(result.screenshot === annotated)
        XCTAssertEqual(recognitions, 1)
    }

    func testEmptySelectionStillUsesOCR() async throws {
        let image = try makeImage(width: 2)
        var recognitions = 0
        let service = TextExtractorService(
            captureScreenshot: { _, _, _ in (image, image) },
            recognizeText: { _ in
                recognitions += 1
                return OCRResult(fullText: "screen fallback", lineNearestCenter: nil)
            },
            selectedTextReader: { _, _ in "" }
        )

        let result = await service.extract(at: .zero, processIdentifier: 101)

        XCTAssertEqual(result.queryText, "screen fallback")
        XCTAssertEqual(recognitions, 1)
    }

    func testSelectionLookupSurvivesUnavailableScreenshot() async {
        var recognitions = 0
        let service = TextExtractorService(
            captureScreenshot: { _, _, _ in nil },
            recognizeText: { _ in
                recognitions += 1
                return nil
            },
            selectedTextReader: { _, _ in "live selection" }
        )

        let result = await service.extract(at: .zero, processIdentifier: 101)

        XCTAssertEqual(result.queryText, "live selection")
        XCTAssertNil(result.rawScreenshot)
        XCTAssertNil(result.screenshot)
        XCTAssertEqual(recognitions, 0)
    }

    private func makeImage(width: Int) throws -> CGImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try XCTUnwrap(bitmap.cgImage)
    }
}
