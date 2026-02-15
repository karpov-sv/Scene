import Foundation

final class OpenAICompatibleAIService: AIProviderServiceBase, @unchecked Sendable {
    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct StreamOptions: Codable {
        let include_usage: Bool
    }

    private struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let max_tokens: Int
        let stream: Bool
        let stream_options: StreamOptions?
    }

    private struct ProviderUsage: Codable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }

    private struct ModelsResponse: Codable {
        struct ModelDescriptor: Codable {
            let id: String
        }

        struct ProviderError: Codable {
            let message: String
        }

        let data: [ModelDescriptor]?
        let error: ProviderError?
    }

    private struct ChatResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let role: String
                let content: String
            }
            let message: Message
        }

        struct ProviderError: Codable {
            let message: String
        }

        let choices: [Choice]?
        let error: ProviderError?
        let usage: ProviderUsage?
    }

    private struct ChatStreamChunk: Codable {
        struct Choice: Codable {
            struct Delta: Codable {
                let role: String?
                let content: String?
            }

            let delta: Delta?
            let finish_reason: String?
        }

        struct ProviderError: Codable {
            let message: String
        }

        let choices: [Choice]?
        let error: ProviderError?
        let usage: ProviderUsage?
    }

    override func generateTextResult(
        _ request: TextGenerationRequest,
        settings: GenerationSettings,
        onPartial: (@MainActor (String) -> Void)?
    ) async throws -> TextGenerationResult {
        try validateModel(in: request)

        let endpoint = try makeChatCompletionsURL(from: settings.endpoint)
        let shouldStream = settings.enableStreaming

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = normalizedTimeout(from: settings.requestTimeoutSeconds)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            urlRequest.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload = ChatRequest(
            model: request.model,
            messages: [
                ChatMessage(role: "system", content: request.systemPrompt),
                ChatMessage(role: "user", content: request.userPrompt)
            ],
            temperature: request.temperature,
            max_tokens: request.maxTokens,
            stream: shouldStream,
            stream_options: nil
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)

        if shouldStream {
            return try await generateStreamingText(urlRequest: urlRequest, onPartial: onPartial)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.badResponse("Missing HTTP response")
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)

        if !(200..<300).contains(http.statusCode) {
            let providerMessage = decoded.error?.message ?? "HTTP \(http.statusCode)"
            throw AIServiceError.requestFailed(providerMessage)
        }

        if let providerError = decoded.error?.message, !providerError.isEmpty {
            throw AIServiceError.requestFailed(providerError)
        }

        guard let content = decoded.choices?.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AIServiceError.badResponse("No completion content in response")
        }

        return TextGenerationResult(
            text: content,
            usage: tokenUsage(from: decoded.usage)
        )
    }

    func makeChatRequestPreview(request: TextGenerationRequest, settings: GenerationSettings) throws -> AIRequestPreview {
        try validateModel(in: request)

        let endpoint = try makeChatCompletionsURL(from: settings.endpoint)
        let shouldStream = settings.enableStreaming

        let payload = ChatRequest(
            model: request.model,
            messages: [
                ChatMessage(role: "system", content: request.systemPrompt),
                ChatMessage(role: "user", content: request.userPrompt)
            ],
            temperature: request.temperature,
            max_tokens: request.maxTokens,
            stream: shouldStream,
            stream_options: nil
        )

        let bodies = try previewBodyStrings(for: payload)

        var headers = [AIRequestPreview.Header(name: "Content-Type", value: "application/json")]
        if !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            headers.append(AIRequestPreview.Header(name: "Authorization", value: "Bearer \(settings.apiKey)"))
        }

        return AIRequestPreview(
            url: endpoint.absoluteString,
            method: "POST",
            headers: headers,
            bodyJSON: bodies.rawJSON,
            bodyHumanReadable: bodies.humanReadable
        )
    }

    private func generateStreamingText(
        urlRequest: URLRequest,
        onPartial: (@MainActor (String) -> Void)?
    ) async throws -> TextGenerationResult {
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.badResponse("Missing HTTP response")
        }

        if !(200..<300).contains(http.statusCode) {
            let data = try await collectData(from: bytes)
            let message = providerErrorMessage(from: data, statusCode: http.statusCode)
            throw AIServiceError.requestFailed(message)
        }

        var accumulated = ""
        var usage: TokenUsage?

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }

            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" {
                break
            }

            guard let data = payload.data(using: .utf8) else {
                continue
            }

            guard let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else {
                continue
            }

            if let providerError = chunk.error?.message, !providerError.isEmpty {
                throw AIServiceError.requestFailed(providerError)
            }

            if let chunkUsage = tokenUsage(from: chunk.usage) {
                usage = chunkUsage
            }

            if let delta = chunk.choices?.first?.delta?.content, !delta.isEmpty {
                accumulated += delta
                if let onPartial {
                    await onPartial(accumulated)
                }
            }
        }

        let final = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else {
            throw AIServiceError.badResponse("No completion content in response")
        }
        return TextGenerationResult(text: final, usage: usage)
    }

    func fetchAvailableModels(settings: GenerationSettings) async throws -> [String] {
        let endpoint = try makeModelsURL(from: settings.endpoint)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = normalizedTimeout(from: settings.requestTimeoutSeconds)
        if !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.badResponse("Missing HTTP response")
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)

        if !(200..<300).contains(http.statusCode) {
            let providerMessage = decoded.error?.message ?? "HTTP \(http.statusCode)"
            throw AIServiceError.requestFailed(providerMessage)
        }

        if let providerError = decoded.error?.message, !providerError.isEmpty {
            throw AIServiceError.requestFailed(providerError)
        }

        return sortedModelIDs((decoded.data ?? []).map(\.id))
    }

    private func makeChatCompletionsURL(from endpoint: String) throws -> URL {
        let base = try makeBaseV1URL(
            from: endpoint,
            removingSuffixes: ["/chat/completions", "/models"]
        )
        return base
            .appendingPathComponent("chat", isDirectory: false)
            .appendingPathComponent("completions", isDirectory: false)
    }

    private func makeModelsURL(from endpoint: String) throws -> URL {
        let base = try makeBaseV1URL(
            from: endpoint,
            removingSuffixes: ["/chat/completions", "/models"]
        )
        return base.appendingPathComponent("models", isDirectory: false)
    }

    private func providerErrorMessage(from data: Data, statusCode: Int) -> String {
        if let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
           let message = decoded.error?.message,
           !message.isEmpty {
            return message
        }

        if let decoded = try? JSONDecoder().decode(ChatStreamChunk.self, from: data),
           let message = decoded.error?.message,
           !message.isEmpty {
            return message
        }

        return fallbackProviderErrorMessage(from: data, statusCode: statusCode)
    }

    private func tokenUsage(from usage: ProviderUsage?) -> TokenUsage? {
        guard let usage else { return nil }
        return TokenUsage(
            promptTokens: usage.prompt_tokens,
            completionTokens: usage.completion_tokens,
            totalTokens: usage.total_tokens
        )
    }
}
