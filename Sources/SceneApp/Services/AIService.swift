import Foundation

protocol AIService {
    func generateText(_ request: TextGenerationRequest, settings: GenerationSettings) async throws -> String
}

struct LocalMockAIService: AIService {
    func generateText(_ request: TextGenerationRequest, settings: GenerationSettings) async throws -> String {
        try await Task.sleep(nanoseconds: 800_000_000)

        let beat = extractField("BEAT:", from: request.userPrompt)
        let context = extractField("CONTEXT:", from: request.userPrompt)

        var output = ""
        if !beat.isEmpty {
            output += "\(beat)"
        } else {
            output += "The next moment unfolded with careful inevitability."
        }

        if !context.isEmpty {
            output += " \n\n(Integrated context cues from compendium and nearby scenes.)"
        }

        output += "\n\n[Local Mock Provider] Replace with a real provider in Settings to generate model output."
        return output
    }

    private func extractField(_ marker: String, from text: String) -> String {
        guard let markerRange = text.range(of: marker) else { return "" }
        let tail = text[markerRange.upperBound...]
        let lines = tail
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.first ?? ""
    }
}
