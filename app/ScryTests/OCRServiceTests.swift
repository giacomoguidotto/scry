import AppKit
import Vision
import XCTest
@testable import Scry

final class OCRServiceTests: XCTestCase {
    private enum RecognitionError: Error {
        case failed
    }

    func testRequestErrorFollowedByHandlerErrorReturnsNil() async throws {
        let image = try makeImage()
        var performCount = 0
        let service = OCRService { request, _ in
            performCount += 1
            XCTAssertNil(request.completionHandler, "Synchronous Vision requests must have no second completion path")
            XCTAssertEqual(request.recognitionLevel, .accurate)
            XCTAssertTrue(request.usesLanguageCorrection)
            // Reproduce Vision reporting a request error before perform throws.
            // If the continuation callback is reintroduced, this catches the crash.
            request.completionHandler?(request, RecognitionError.failed)
            request.completionHandler?(request, RecognitionError.failed)
            throw RecognitionError.failed
        }

        let result = await service.recognizeText(in: image)

        XCTAssertNil(result)
        XCTAssertEqual(performCount, 1)
    }

    func testHandlerErrorWithoutCallbackReturnsNil() async throws {
        let image = try makeImage()
        let service = OCRService { _, _ in throw RecognitionError.failed }

        let result = await service.recognizeText(in: image)

        XCTAssertNil(result)
    }

    func testSuccessfulPerformWithoutObservationsReturnsNil() async throws {
        let image = try makeImage()
        let service = OCRService { _, _ in [] }

        let result = await service.recognizeText(in: image)

        XCTAssertNil(result)
    }

    func testReturnsRecognizedTextAndCenterLine() async throws {
        let image = try makeImage(text: "Scry OCR regression")
        let service = OCRService { _, _ in [RecognizedObservation()] }

        let result = await service.recognizeText(in: image)

        XCTAssertEqual(result?.fullText, "Scry OCR regression")
        XCTAssertEqual(result?.lineNearestCenter, "Scry OCR regression")
    }

    func testMissingObservationsReturnsNil() async throws {
        let image = try makeImage()
        let service = OCRService { _, _ in nil }

        let result = await service.recognizeText(in: image)

        XCTAssertNil(result)
    }

    func testRecognitionRecoversAfterHandlerFailure() async throws {
        let image = try makeImage(text: "Scry OCR regression")
        var performCount = 0
        let service = OCRService { _, _ in
            performCount += 1
            if performCount == 1 { throw RecognitionError.failed }
            return [RecognizedObservation()]
        }

        let failed = await service.recognizeText(in: image)
        let recovered = await service.recognizeText(in: image)

        XCTAssertNil(failed)
        XCTAssertEqual(recovered?.fullText, "Scry OCR regression")
        XCTAssertEqual(performCount, 2)
    }

    func testConcurrentOperationsKeepResultsIndependent() async throws {
        let image = try makeImage(text: "Scry OCR regression")
        let service = OCRService { _, _ in [RecognizedObservation()] }

        await withTaskGroup(of: String?.self) { group in
            for _ in 0..<4 {
                group.addTask { await service.recognizeText(in: image)?.fullText }
            }
            var completed = 0
            for await text in group {
                XCTAssertEqual(text, "Scry OCR regression")
                completed += 1
            }
            XCTAssertEqual(completed, 4)
        }
    }

    func testSystemVisionRecognizesScreenshotWhenAvailable() async throws {
        let image = try makeImage(text: "Scry OCR regression")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            let failure = error as NSError
            throw XCTSkip("System Vision unavailable: \(failure.domain) code \(failure.code)")
        }
        let result = await OCRService().recognizeText(in: image)
        XCTAssertEqual(result?.fullText, "Scry OCR regression")
    }

    private final class RecognizedText: VNRecognizedText {
        override var string: String { "Scry OCR regression" }
    }

    private final class RecognizedObservation: VNRecognizedTextObservation {
        override var boundingBox: CGRect { CGRect(x: 0.2, y: 0.4, width: 0.6, height: 0.2) }

        override func topCandidates(_ maxCandidateCount: Int) -> [VNRecognizedText] {
            maxCandidateCount > 0 ? [RecognizedText()] : []
        }
    }

    private func makeImage(text: String = "") throws -> CGImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 160,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 640, height: 160).fill()
        (text as NSString).draw(at: NSPoint(x: 50, y: 60), withAttributes: [
            .font: NSFont.systemFont(ofSize: 36),
            .foregroundColor: NSColor.black
        ])
        context.flushGraphics()
        return try XCTUnwrap(bitmap.cgImage)
    }
}
