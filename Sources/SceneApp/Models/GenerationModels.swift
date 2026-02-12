import Foundation

struct TokenUsage: Codable, Equatable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var isEstimated: Bool

    init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        isEstimated: Bool = false
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.isEstimated = isEstimated
    }
}

struct TextGenerationResult: Sendable {
    var text: String
    var usage: TokenUsage?
}

struct TextGenerationRequest: Sendable {
    var systemPrompt: String
    var userPrompt: String
    var model: String
    var temperature: Double
    var maxTokens: Int
}

enum AIServiceError: LocalizedError {
    case invalidEndpoint
    case missingModel
    case badResponse(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid endpoint URL."
        case .missingModel:
            return "No model selected."
        case .badResponse(let message):
            return "Unexpected provider response: \(message)"
        case .requestFailed(let message):
            return "Provider request failed: \(message)"
        }
    }
}
