import Foundation

struct OpenAICompatibleAIService: AIService {
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

    func generateText(_ request: TextGenerationRequest, settings: GenerationSettings) async throws -> String {
        guard !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.missingModel
        }

        let endpoint = try makeEndpointURL(from: settings.endpoint)

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
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
            stream: false
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)

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

    private func makeEndpointURL(from endpoint: String) throws -> URL {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIServiceError.invalidEndpoint
        }

        var normalized = trimmed
        if normalized.hasSuffix("/chat/completions") {
            guard let url = URL(string: normalized) else {
                throw AIServiceError.invalidEndpoint
            }
            return url
        }

        if normalized.hasSuffix("/v1") {
            normalized += "/chat/completions"
        } else {
            normalized += "/v1/chat/completions"
        }

        guard let url = URL(string: normalized) else {
            throw AIServiceError.invalidEndpoint
        }
        return url
    }
}
