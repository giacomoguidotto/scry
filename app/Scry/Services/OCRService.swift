import CoreGraphics
import NaturalLanguage
import Vision

struct OCRResult {
    let fullText: String
    let lineNearestCenter: String?
}

final class OCRService {
    private let debugLog = DebugLogStore.shared
    private let performRequest: (VNRecognizeTextRequest, CGImage) throws -> [VNRecognizedTextObservation]?

    init(performRequest: @escaping (VNRecognizeTextRequest, CGImage) throws -> [VNRecognizedTextObservation]? = { request, image in
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return request.results
    }) {
        self.performRequest = performRequest
    }

    /// Performs on-device OCR on the given image and returns recognized text.
    func recognizeText(in image: CGImage) async -> OCRResult? {
        // Vision performs synchronously. Read results only after it returns so a
        // request error and a thrown handler error cannot finish the operation twice.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let observations: [VNRecognizedTextObservation]?
        do {
            observations = try performRequest(request, image)
        } catch {
            debugLog.log("OCR", "Handler error: \(error.localizedDescription)", level: .error)
            return nil
        }

        guard let observations = observations, !observations.isEmpty else {
            debugLog.log("OCR", "No text recognized", level: .debug)
            return nil
        }

        let fullText = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        let centerLine = Self.findLineNearestCenter(observations: observations)

        debugLog.log("OCR", "Recognized \(observations.count) lines, center line: \(centerLine ?? "none")", level: .debug)
        return OCRResult(fullText: fullText, lineNearestCenter: centerLine)
    }

    /// Finds the text line whose bounding box is nearest to the center of the image.
    static func findLineNearestCenter(observations: [VNRecognizedTextObservation]) -> String? {
        let imageCenter = CGPoint(x: 0.5, y: 0.5)
        var bestLine: String?
        var bestDistance: CGFloat = .greatestFiniteMagnitude

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }

            let box = observation.boundingBox
            let center = CGPoint(
                x: box.origin.x + box.width / 2,
                y: box.origin.y + box.height / 2
            )

            let dx = center.x - imageCenter.x
            let dy = center.y - imageCenter.y
            let distance = dx * dx + dy * dy

            if distance < bestDistance {
                bestDistance = distance
                bestLine = candidate.string
            }
        }

        return bestLine
    }
}
