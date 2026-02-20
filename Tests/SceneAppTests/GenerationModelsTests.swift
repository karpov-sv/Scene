import XCTest
@testable import SceneApp

final class GenerationModelsTests: XCTestCase {
    func testTokenUsageInitializerAssignsFields() {
        let usage = TokenUsage(
            promptTokens: 3,
            completionTokens: 5,
            totalTokens: 8,
            isEstimated: true
        )

        XCTAssertEqual(usage.promptTokens, 3)
        XCTAssertEqual(usage.completionTokens, 5)
        XCTAssertEqual(usage.totalTokens, 8)
        XCTAssertTrue(usage.isEstimated)
    }

    func testAIServiceErrorDescriptions() {
        XCTAssertEqual(AIServiceError.invalidEndpoint.errorDescription, "Invalid endpoint URL.")
        XCTAssertEqual(AIServiceError.missingModel.errorDescription, "No model selected.")
        XCTAssertEqual(
            AIServiceError.badResponse("bad payload").errorDescription,
            "Unexpected provider response: bad payload"
        )
        XCTAssertEqual(
            AIServiceError.requestFailed("timeout").errorDescription,
            "Provider request failed: timeout"
        )
    }
}
