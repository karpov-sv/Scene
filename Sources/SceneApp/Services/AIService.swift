import Foundation

protocol AIService {
    func generateText(_ request: TextGenerationRequest, settings: GenerationSettings) async throws -> String
}
