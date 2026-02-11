import Foundation

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
