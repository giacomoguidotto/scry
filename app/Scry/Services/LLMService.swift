import AppKit
import Combine
import Foundation

final class LLMStreamingResponse: ObservableObject {
    @Published var text: String = ""
    @Published var isComplete: Bool = false
    @Published var error: String?

    fileprivate var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }
}

final class LLMService {
    private let debugLog = DebugLogStore.shared

    static let systemPrompt = """
        You are Scry, a macOS assistant that helps users understand what's on their screen. \
        The user triggered Scry while looking at their screen. You will receive a screenshot \
        of what they see. A small colored circle marks the user's cursor position — focus \
        your analysis on the content near that marker.

        Guidelines:
        - If the user selected specific text, explain, define, or provide context for that text.
        - If no text was selected, focus on whatever is near the cursor marker and describe or explain it.
        - If the screenshot shows code, explain what it does.
        - If it shows a UI element, icon, or image, describe it and explain its purpose.
        - Be concise: 2-4 sentences unless the topic warrants more detail.
        - When extracted text is provided alongside the screenshot, use both — the text may \
        include content scrolled off-screen that the screenshot doesn't show.
        """

    /// Starts a streaming LLM analysis from an extraction result.
    func analyze(_ result: ExtractionResult) -> LLMStreamingResponse {
        let response = LLMStreamingResponse()
        let settings = AppSettings.shared
        let providerType = settings.aiProviderType

        if providerType != .ollama, settings.aiAPIKey.isEmpty {
            response.error = "No API key configured. Open Preferences \u{2192} AI to set one."
            response.isComplete = true
            return response
        }

        // Encode screenshot (use annotated version with cursor ring)
        let imageData: String?
        if let screenshot = result.screenshot {
            imageData = jpegBase64(from: screenshot)
        } else {
            imageData = nil
        }

        // Build user prompt based on what we have
        let userPrompt = buildUserPrompt(result: result)

        let model = settings.aiModel
        let apiKey = settings.aiAPIKey

        guard let url = URL(string: endpointURL(for: providerType, settings: settings)) else {
            response.error = "Invalid endpoint URL."
            response.isComplete = true
            return response
        }

        response.task = Task {
            do {
                let request = try buildRequest(RequestConfig(
                    url: url,
                    providerType: providerType,
                    model: model,
                    apiKey: apiKey,
                    imageBase64: imageData,
                    userPrompt: userPrompt
                ))

                let (bytes, httpResponse) = try await URLSession.shared.bytes(for: request)

                if let http = httpResponse as? HTTPURLResponse, http.statusCode != 200 {
                    var body = ""
                    for try await line in bytes.lines {
                        body += line
                        if body.count > 500 { break }
                    }
                    await MainActor.run {
                        response.error = "API error \(http.statusCode): \(body)"
                        response.isComplete = true
                    }
                    return
                }

                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    if let text = parseSSELine(line, providerType: providerType) {
                        await MainActor.run {
                            response.text += text
                        }
                    }
                }

                await MainActor.run {
                    response.isComplete = true
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        response.error = error.localizedDescription
                        response.isComplete = true
                    }
                }
            }
        }

        return response
    }

    /// Legacy compatibility: analyze with raw image and query string.
    func analyzeImage(_ image: CGImage?, query: String? = nil) -> LLMStreamingResponse {
        let result = ExtractionResult(
            screenshot: image,
            rawScreenshot: image,
            cursorPosition: .zero,
            axText: query,
            ocrText: nil,
            ocrCenterLine: nil
        )
        return analyze(result)
    }

    // MARK: - Prompt Building

    private func buildUserPrompt(result: ExtractionResult) -> String {
        let hasImage = result.screenshot != nil
        let hasText = !(result.axText ?? "").isEmpty

        if hasText && hasImage {
            // swiftlint:disable:next force_unwrapping
            let text = result.axText!
            return "The user selected this text: \"\(text)\"\n\n"
                + "The screenshot shows the area they were looking at. "
                + "Explain or provide context for the selected text."
        }

        if hasImage {
            return "Focus on the content near the cursor marker. "
                + "What is it? Describe and provide helpful context."
        }

        if hasText {
            // swiftlint:disable:next force_unwrapping
            return "The user selected: \"\(result.axText!)\"\n\nExplain or provide context."
        }

        return "What is on the screen? Describe what you see."
    }

    // MARK: - Endpoint Resolution

    private func endpointURL(for provider: AIProviderType, settings: AppSettings) -> String {
        switch provider {
        case .claude: return Constants.AIConfig.claudeEndpoint
        case .openai: return Constants.AIConfig.openAIEndpoint
        case .ollama: return Constants.AIConfig.ollamaEndpoint
        case .custom: return settings.aiCustomEndpoint
        }
    }

    // MARK: - Request Building

    private struct RequestConfig {
        let url: URL
        let providerType: AIProviderType
        let model: String
        let apiKey: String
        let imageBase64: String?
        let userPrompt: String
    }

    private func buildRequest(_ config: RequestConfig) throws -> URLRequest {
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch config.providerType {
        case .claude:
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .ollama:
            break
        case .openai, .custom:
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: Data
        switch config.providerType {
        case .claude:
            body = try buildClaudeBody(config)
        case .openai, .ollama, .custom:
            body = try buildOpenAIBody(config)
        }

        request.httpBody = body
        return request
    }

    private func buildClaudeBody(_ config: RequestConfig) throws -> Data {
        var content: [[String: Any]] = []
        if let imageBase64 = config.imageBase64 {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageBase64,
                ],
            ])
        }
        content.append(["type": "text", "text": config.userPrompt])

        let payload: [String: Any] = [
            "model": config.model,
            "max_tokens": Constants.AIConfig.maxTokens,
            "stream": true,
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": content]],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func buildOpenAIBody(_ config: RequestConfig) throws -> Data {
        var userContent: Any
        if let imageBase64 = config.imageBase64 {
            userContent = [
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]],
                ["type": "text", "text": config.userPrompt],
            ] as [[String: Any]]
        } else {
            userContent = config.userPrompt
        }

        let payload: [String: Any] = [
            "model": config.model,
            "max_tokens": Constants.AIConfig.maxTokens,
            "stream": true,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - SSE Parsing

    private func parseSSELine(_ line: String, providerType: AIProviderType) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let jsonStr = String(line.dropFirst(6))
        if jsonStr == "[DONE]" { return nil }

        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch providerType {
        case .claude:
            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return text
            }
        case .openai, .ollama, .custom:
            if let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                return content
            }
        }
        return nil
    }

    // MARK: - Image Encoding

    private func jpegBase64(from cgImage: CGImage) -> String? {
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        return jpeg.base64EncodedString()
    }
}
