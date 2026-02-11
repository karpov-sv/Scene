import Foundation

struct OpenAICompatibleAIService: AIService {
    struct RequestPreview {
        struct Header {
            let name: String
            let value: String
        }

        let url: String
        let method: String
        let headers: [Header]
        let bodyJSON: String
    }

    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let max_tokens: Int
        let stream: Bool
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
    }

    func generateText(_ request: TextGenerationRequest, settings: GenerationSettings) async throws -> String {
        try await generateText(request, settings: settings, onPartial: nil)
    }

    func makeChatRequestPreview(request: TextGenerationRequest, settings: GenerationSettings) throws -> RequestPreview {
        guard !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.missingModel
        }

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
            stream: shouldStream
        )

        let bodyData = try prettyPrintedJSONData(payload)
        let body = String(data: bodyData, encoding: .utf8) ?? "{}"

        var headers = [RequestPreview.Header(name: "Content-Type", value: "application/json")]
        if !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            headers.append(RequestPreview.Header(name: "Authorization", value: "Bearer \(settings.apiKey)"))
        }

        return RequestPreview(
            url: endpoint.absoluteString,
            method: "POST",
            headers: headers,
            bodyJSON: body
        )
    }

    func generateText(
        _ request: TextGenerationRequest,
        settings: GenerationSettings,
        onPartial: (@MainActor (String) -> Void)?
    ) async throws -> String {
        guard !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.missingModel
        }

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

        return content
    }

    private func generateStreamingText(
        urlRequest: URLRequest,
        onPartial: (@MainActor (String) -> Void)?
    ) async throws -> String {
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
        return final
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

        let modelIDs = Set(
            (decoded.data ?? [])
                .map(\.id)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        return modelIDs.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func makeChatCompletionsURL(from endpoint: String) throws -> URL {
        let base = try makeBaseV1URL(from: endpoint)
        return base
            .appendingPathComponent("chat", isDirectory: false)
            .appendingPathComponent("completions", isDirectory: false)
    }

    private func makeModelsURL(from endpoint: String) throws -> URL {
        let base = try makeBaseV1URL(from: endpoint)
        return base.appendingPathComponent("models", isDirectory: false)
    }

    private func makeBaseV1URL(from endpoint: String) throws -> URL {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIServiceError.invalidEndpoint
        }

        guard var components = URLComponents(string: trimmed), let rawPath = components.path.removingPercentEncoding else {
            throw AIServiceError.invalidEndpoint
        }

        let normalizedPath: String
        if rawPath.hasSuffix("/chat/completions") {
            normalizedPath = String(rawPath.dropLast("/chat/completions".count))
        } else {
            normalizedPath = rawPath
        }

        let trimmedPath = normalizedPath.hasSuffix("/")
            ? String(normalizedPath.dropLast())
            : normalizedPath

        if trimmedPath.hasSuffix("/v1") {
            components.path = trimmedPath
        } else {
            components.path = trimmedPath + "/v1"
        }

        guard let normalizedURL = components.url else {
            throw AIServiceError.invalidEndpoint
        }
        return normalizedURL
    }

    private func normalizedTimeout(from timeout: Double) -> TimeInterval {
        let clamped = min(max(timeout, 1), 3600)
        return TimeInterval(clamped)
    }

    private func prettyPrintedJSONData<T: Encodable>(_ value: T) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: encoded)
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
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

        if let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return "HTTP \(statusCode): \(String(raw.prefix(280)))"
        }

        return "HTTP \(statusCode)"
    }
}
