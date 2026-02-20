import XCTest
@testable import SceneApp

final class AIProviderServiceBaseTests: XCTestCase {
    private let service = AIProviderServiceBase()

    func testValidateModelRejectsEmptyModelName() {
        let request = TextGenerationRequest(
            systemPrompt: "",
            userPrompt: "",
            model: "   ",
            temperature: 0.8,
            maxTokens: 100
        )

        XCTAssertThrowsError(try service.validateModel(in: request)) { error in
            guard case AIServiceError.missingModel = error else {
                XCTFail("Expected missingModel, got \(error)")
                return
            }
        }
    }

    func testNormalizedTimeoutClampsToAllowedRange() {
        XCTAssertEqual(service.normalizedTimeout(from: 0), 1)
        XCTAssertEqual(service.normalizedTimeout(from: 45), 45)
        XCTAssertEqual(service.normalizedTimeout(from: 9_999), 3_600)
    }

    func testPreviewBodyStringsReturnsRawAndHumanReadableRepresentations() throws {
        struct Payload: Encodable {
            let model: String
            let items: [Int]
            let note: String
        }

        let payload = Payload(
            model: "test-model",
            items: [1, 2],
            note: "line1\nline2"
        )

        let preview = try service.previewBodyStrings(for: payload)
        XCTAssertTrue(preview.rawJSON.contains("\"model\""))
        XCTAssertTrue(preview.rawJSON.contains("\"items\""))

        XCTAssertTrue(preview.humanReadable.contains("model:"))
        XCTAssertTrue(preview.humanReadable.contains("items:"))
        XCTAssertTrue(preview.humanReadable.contains("line1"))
        XCTAssertTrue(preview.humanReadable.contains("line2"))
    }

    func testFallbackProviderErrorMessageUsesStatusAndBodySnippet() {
        let longMessage = String(repeating: "x", count: 500)
        let data = Data(longMessage.utf8)

        let message = service.fallbackProviderErrorMessage(from: data, statusCode: 429)
        XCTAssertTrue(message.hasPrefix("HTTP 429: "))
        XCTAssertLessThanOrEqual(message.count, "HTTP 429: ".count + 280)
    }

    func testSortedModelIDsDeduplicatesAndSorts() {
        let sorted = service.sortedModelIDs([
            " zeta ",
            "beta",
            "beta",
            "",
            "Alpha"
        ])

        XCTAssertEqual(sorted, ["Alpha", "beta", "zeta"])
    }

    func testMakeBaseV1URLNormalizesEndpointAndRemovesKnownSuffixes() throws {
        let stripped = try service.makeBaseV1URL(
            from: "https://example.com/chat/completions",
            removingSuffixes: ["/chat/completions", "/models"]
        )
        XCTAssertEqual(stripped.absoluteString, "https://example.com/v1")

        let existingV1 = try service.makeBaseV1URL(
            from: "https://example.com/api/v1",
            removingSuffixes: []
        )
        XCTAssertEqual(existingV1.absoluteString, "https://example.com/api/v1")

        let appended = try service.makeBaseV1URL(
            from: "https://example.com/custom/path",
            removingSuffixes: []
        )
        XCTAssertEqual(appended.absoluteString, "https://example.com/custom/path/v1")
    }

    func testMakeBaseV1URLRejectsInvalidEndpoint() {
        XCTAssertThrowsError(
            try service.makeBaseV1URL(from: "   ", removingSuffixes: ["/models"])
        ) { error in
            guard case AIServiceError.invalidEndpoint = error else {
                XCTFail("Expected invalidEndpoint, got \(error)")
                return
            }
        }
    }
}
