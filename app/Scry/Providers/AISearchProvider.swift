import CoreGraphics
import Foundation

final class AISearchProvider: SearchProvider {
    let id = "ai"
    let name = "AI"
    let iconSymbolName = "sparkles"
    let supportsNativeRendering = true

    /// Set by AppDelegate before triggering search.
    var extractionResult: ExtractionResult?

    /// The current streaming response, observed by AIResultView.
    private(set) var currentResponse: LLMStreamingResponse?

    private let llmService = LLMService()

    /// Starts analysis and returns the streaming response immediately (no waiting).
    func startAnalysis() -> LLMStreamingResponse {
        let result = extractionResult ?? ExtractionResult(
            screenshot: nil, rawScreenshot: nil, cursorPosition: .zero,
            axText: nil, ocrText: nil, ocrCenterLine: nil
        )
        let response = llmService.analyze(result)
        currentResponse = response
        return response
    }

    func search(query: String) async throws -> [SearchResult] {
        let response = startAnalysis()

        while !response.isComplete {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if let error = response.error {
            return [SearchResult(title: "Error", snippet: error, url: nil, imageURL: nil)]
        }

        return [SearchResult(title: "AI Analysis", snippet: response.text, url: nil, imageURL: nil)]
    }
}
