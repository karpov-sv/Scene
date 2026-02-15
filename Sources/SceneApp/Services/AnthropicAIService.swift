import Foundation

final class AnthropicAIService: AIProviderServiceBase, @unchecked Sendable {
    private static let anthropicVersion = "2023-06-01"

    private struct TextPart: Codable {
        let type: String
        let text: String
    }

    private struct Message: Codable {
        let role: String
        let content: [TextPart]
    }

    private struct MessagesRequest: Codable {
        let model: String
        let max_tokens: Int
        let temperature: Double
        let system: String
        let messages: [Message]
        let stream: Bool
    }

    private struct ResponseUsage: Codable {
        let input_tokens: Int?
        let output_tokens: Int?
    }

    private struct ResponseContentBlock: Codable {
        let type: String?
        let text: String?
    }

    private struct MessagesResponse: Codable {
        let content: [ResponseContentBlock]?
        let usage: ResponseUsage?
    }

    private struct StreamDelta: Codable {
        let type: String?
        let text: String?
    }

    private struct StreamMessage: Codable {
        let usage: ResponseUsage?
    }

    private struct StreamEvent: Codable {
        let type: String?
        let delta: StreamDelta?
        let message: StreamMessage?
        let usage: ResponseUsage?
        let content_block: ResponseContentBlock?
    }

    private struct ProviderErrorEnvelope: Codable {
        struct ProviderErrorBody: Codable {
            let message: String?
        }

        let error: ProviderErrorBody?
        let message: String?
    }

    private struct ModelsResponse: Codable {
        struct ModelDescriptor: Codable {
            let id: String?
        }

        let data: [ModelDescriptor]?
    }

    override func generateTextResult(
        _ request: TextGenerationRequest,
        settings: GenerationSettings,
        onPartial: (@MainActor (String) -> Void)?
    ) async throws -> TextGenerationResult {
        try validateModel(in: request)

        let endpoint = try makeMessagesURL(from: settings.endpoint)
        let shouldStream = settings.enableStreaming

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = normalizedTimeout(from: settings.requestTimeoutSeconds)
        applyRequestHeaders(to: &urlRequest, apiKey: settings.apiKey)

        let payload = MessagesRequest(
            model: request.model,
            max_tokens: request.maxTokens,
            temperature: request.temperature,
            system: request.systemPrompt,
            messages: [
                Message(
                    role: "user",
                    content: [TextPart(type: "text", text: request.userPrompt)]
                )
            ],
            stream: shouldStream
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)

        if shouldStream {
            return try await generateStreamingText(urlRequest: urlRequest, onPartial: onPartial)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.badResponse("Missing HTTP response")
        }

        if !(200..<300).contains(http.statusCode) {
            throw AIServiceError.requestFailed(providerErrorMessage(from: data, statusCode: http.statusCode))
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        let text = decoded.content?
            .filter { $0.type == nil || $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else {
            throw AIServiceError.badResponse("No completion content in response")
        }

        return TextGenerationResult(
            text: text,
            usage: tokenUsage(from: decoded.usage)
        )
    }

    func makeRequestPreview(
        request: TextGenerationRequest,
        settings: GenerationSettings
    ) throws -> AIRequestPreview {
        try validateModel(in: request)

        let endpoint = try makeMessagesURL(from: settings.endpoint)
        let payload = MessagesRequest(
            model: request.model,
            max_tokens: request.maxTokens,
            temperature: request.temperature,
            system: request.systemPrompt,
            messages: [
                Message(
                    role: "user",
                    content: [TextPart(type: "text", text: request.userPrompt)]
                )
            ],
            stream: settings.enableStreaming
        )

        let bodies = try previewBodyStrings(for: payload)

        var headers = [
            AIRequestPreview.Header(name: "Content-Type", value: "application/json"),
            AIRequestPreview.Header(name: "anthropic-version", value: Self.anthropicVersion)
        ]
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            headers.append(AIRequestPreview.Header(name: "x-api-key", value: apiKey))
        }

        return AIRequestPreview(
            url: endpoint.absoluteString,
            method: "POST",
            headers: headers,
            bodyJSON: bodies.rawJSON,
            bodyHumanReadable: bodies.humanReadable
        )
    }

    func fetchAvailableModels(settings: GenerationSettings) async throws -> [String] {
        let endpoint = try makeModelsURL(from: settings.endpoint)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = normalizedTimeout(from: settings.requestTimeoutSeconds)
        applyRequestHeaders(to: &request, apiKey: settings.apiKey, includeContentType: false)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.badResponse("Missing HTTP response")
        }

        if !(200..<300).contains(http.statusCode) {
            throw AIServiceError.requestFailed(providerErrorMessage(from: data, statusCode: http.statusCode))
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return sortedModelIDs((decoded.data ?? []).compactMap(\.id))
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
            throw AIServiceError.requestFailed(providerErrorMessage(from: data, statusCode: http.statusCode))
        }

        var accumulated = ""
        var inputTokens: Int?
        var outputTokens: Int?

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }

            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" {
                break
            }

            guard let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else {
                continue
            }

            if let usage = event.usage ?? event.message?.usage {
                if let input = usage.input_tokens {
                    inputTokens = input
                }
                if let output = usage.output_tokens {
                    outputTokens = output
                }
            }

            if let delta = event.delta?.text, !delta.isEmpty {
                accumulated += delta
                if let onPartial {
                    await onPartial(accumulated)
                }
                continue
            }

            if let startText = event.content_block?.text, !startText.isEmpty {
                accumulated += startText
                if let onPartial {
                    await onPartial(accumulated)
                }
            }
        }

        let final = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else {
            throw AIServiceError.badResponse("No completion content in response")
        }

        let usage = tokenUsage(
            from: ResponseUsage(input_tokens: inputTokens, output_tokens: outputTokens)
        )
        return TextGenerationResult(text: final, usage: usage)
    }

    private func makeMessagesURL(from endpoint: String) throws -> URL {
        let base = try makeBaseV1URL(
            from: endpoint,
            removingSuffixes: ["/v1/messages", "/v1/models", "/messages", "/models"]
        )
        return base.appendingPathComponent("messages", isDirectory: false)
    }

    private func makeModelsURL(from endpoint: String) throws -> URL {
        let base = try makeBaseV1URL(
            from: endpoint,
            removingSuffixes: ["/v1/messages", "/v1/models", "/messages", "/models"]
        )
        return base.appendingPathComponent("models", isDirectory: false)
    }

    private func applyRequestHeaders(
        to request: inout URLRequest,
        apiKey: String,
        includeContentType: Bool = true
    ) {
        if includeContentType {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        }
    }

    private func providerErrorMessage(from data: Data, statusCode: Int) -> String {
        if let decoded = try? JSONDecoder().decode(ProviderErrorEnvelope.self, from: data) {
            if let message = decoded.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return message
            }
            if let message = decoded.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return message
            }
        }

        return fallbackProviderErrorMessage(from: data, statusCode: statusCode)
    }

    private func tokenUsage(from usage: ResponseUsage?) -> TokenUsage? {
        guard let usage else { return nil }
        let prompt = usage.input_tokens
        let completion = usage.output_tokens
        let total: Int? = {
            switch (prompt, completion) {
            case let (.some(p), .some(c)):
                return p + c
            case let (.some(p), .none):
                return p
            case let (.none, .some(c)):
                return c
            case (.none, .none):
                return nil
            }
        }()

        return TokenUsage(
            promptTokens: prompt,
            completionTokens: completion,
            totalTokens: total
        )
    }
}
