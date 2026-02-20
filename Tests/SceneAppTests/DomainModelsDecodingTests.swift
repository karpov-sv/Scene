import XCTest
@testable import SceneApp

final class DomainModelsDecodingTests: XCTestCase {
    func testWorkshopSessionDecodingDefaultsContextFlagsToTrue() throws {
        let raw = """
        {
          "id": "00000000-0000-0000-0000-000000000777",
          "name": "Session",
          "messages": [],
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(WorkshopSession.self, from: Data(raw.utf8))
        XCTAssertTrue(session.useSceneContext)
        XCTAssertTrue(session.useCompendiumContext)
    }

    func testGenerationSettingsDecodingNormalizesSelectionAndFallsBackToModel() throws {
        let decoder = JSONDecoder()

        let explicitSelectionJSON = """
        {
          "provider": "openAI",
          "endpoint": "",
          "apiKey": "",
          "model": "fallback-model",
          "generationModelSelection": [" model-a ", "model-a", "", "model-b"],
          "temperature": 0.8,
          "maxTokens": 700,
          "defaultSystemPrompt": "sys"
        }
        """
        let normalized = try decoder.decode(GenerationSettings.self, from: Data(explicitSelectionJSON.utf8))
        XCTAssertEqual(normalized.generationModelSelection, ["model-a", "model-b"])

        let fallbackSelectionJSON = """
        {
          "provider": "openAI",
          "endpoint": "",
          "apiKey": "",
          "model": "fallback-model",
          "temperature": 0.8,
          "maxTokens": 700,
          "defaultSystemPrompt": "sys"
        }
        """
        let fallback = try decoder.decode(GenerationSettings.self, from: Data(fallbackSelectionJSON.utf8))
        XCTAssertEqual(fallback.generationModelSelection, ["fallback-model"])
    }

    func testStoryProjectDecodingBackfillsOptionalMapsWhenMissing() throws {
        var project = StoryProject.starter()
        project.sceneContextSceneSummarySelection = [UUID().uuidString: [UUID()]]
        project.sceneContextChapterSummarySelection = [UUID().uuidString: [UUID()]]
        project.sceneNarrativeStates = [UUID().uuidString: SceneNarrativeState(pov: "third")]
        project.rollingSceneMemoryByScene = [UUID().uuidString: RollingSceneMemory(summary: "mem", sourceContentHash: "x")]
        project.rollingChapterMemoryByChapter = [UUID().uuidString: RollingChapterMemory(summary: "mem", sourceFingerprint: "x")]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let encoded = try encoder.encode(project)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded, options: []) as? [String: Any]
        )
        object.removeValue(forKey: "sceneContextSceneSummarySelection")
        object.removeValue(forKey: "sceneContextChapterSummarySelection")
        object.removeValue(forKey: "sceneNarrativeStates")
        object.removeValue(forKey: "rollingSceneMemoryByScene")
        object.removeValue(forKey: "rollingChapterMemoryByChapter")

        let normalizedData = try JSONSerialization.data(withJSONObject: object, options: [])
        let decoded = try decoder.decode(StoryProject.self, from: normalizedData)

        XCTAssertEqual(decoded.sceneContextSceneSummarySelection, [:])
        XCTAssertEqual(decoded.sceneContextChapterSummarySelection, [:])
        XCTAssertEqual(decoded.sceneNarrativeStates, [:])
        XCTAssertEqual(decoded.rollingSceneMemoryByScene, [:])
        XCTAssertEqual(decoded.rollingChapterMemoryByChapter, [:])
    }
}
