import Foundation
import XCTest
@testable import SceneApp

final class AnthropicAIServiceTests: XCTestCase {
    private let service = AnthropicAIService()

    func testMakeRequestPreviewBuildsNormalizedURLAndAnthropicHeaders() throws {
        var settings = GenerationSettings.default
        settings.provider = .anthropic
        settings.endpoint = "https://api.anthropic.com/v1/models"
        settings.apiKey = "api-key"
        settings.enableStreaming = false

        let request = TextGenerationRequest(
            systemPrompt: "sys",
            userPrompt: "user",
            model: "claude-test",
            temperature: 0.2,
            maxTokens: 512
        )

        let preview = try service.makeRequestPreview(request: request, settings: settings)
        XCTAssertEqual(preview.url, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(preview.method, "POST")
        XCTAssertTrue(preview.headers.contains { $0.name == "Content-Type" && $0.value == "application/json" })
        XCTAssertTrue(preview.headers.contains { $0.name == "anthropic-version" && $0.value == "2023-06-01" })
        XCTAssertTrue(preview.headers.contains { $0.name == "x-api-key" && $0.value == "api-key" })
        XCTAssertTrue(preview.bodyJSON.contains("\"stream\" : false"))
    }

    func testGenerateTextResultParsesTextBlocksAndUsage() async throws {
        var settings = GenerationSettings.default
        settings.provider = .anthropic
        settings.endpoint = "https://api.anthropic.com"
        settings.apiKey = "api-key"
        settings.enableStreaming = false

        let request = TextGenerationRequest(
            systemPrompt: "sys",
            userPrompt: "user",
            model: "claude-test",
            temperature: 0.3,
            maxTokens: 300
        )

        let responseJSON = """
        {
          "content": [
            { "type": "text", "text": "hello " },
            { "type": "tool", "text": "ignored" },
            { "text": "world" }
          ],
          "usage": {
            "input_tokens": 9,
            "output_tokens": 6
          }
        }
        """

        let result = try await withMockedHTTPResponses(
            handler: { req in
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(req.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(responseJSON.utf8))
            },
            {
                try await self.service.generateTextResult(request, settings: settings, onPartial: nil)
            }
        )

        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.usage, TokenUsage(promptTokens: 9, completionTokens: 6, totalTokens: 15))

        let captured = HTTPTestStubURLProtocol.recordedRequests()
        let sentRequest = try XCTUnwrap(captured.first)
        XCTAssertEqual(sentRequest.httpMethod, "POST")
        XCTAssertEqual(sentRequest.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "x-api-key"), "api-key")
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testGenerateTextResultSurfacesProviderMessageOnHTTPFailure() async {
        var settings = GenerationSettings.default
        settings.provider = .anthropic
        settings.endpoint = "https://api.anthropic.com"
        settings.enableStreaming = false

        let request = TextGenerationRequest(
            systemPrompt: "sys",
            userPrompt: "user",
            model: "claude-test",
            temperature: 0.3,
            maxTokens: 300
        )

        do {
            _ = try await withMockedHTTPResponses(
                handler: { req in
                    let response = HTTPURLResponse(
                        url: try XCTUnwrap(req.url),
                        statusCode: 403,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    return (response, Data(#"{"error":{"message":"forbidden"}}"#.utf8))
                },
                {
                    try await self.service.generateTextResult(request, settings: settings, onPartial: nil)
                }
            )
            XCTFail("Expected requestFailed")
        } catch let error as AIServiceError {
            guard case .requestFailed(let message) = error else {
                XCTFail("Expected requestFailed, got \(error)")
                return
            }
            XCTAssertEqual(message, "forbidden")
        } catch {
            XCTFail("Expected AIServiceError, got \(error)")
        }
    }

    func testFetchAvailableModelsParsesAndNormalizesIDs() async throws {
        var settings = GenerationSettings.default
        settings.provider = .anthropic
        settings.endpoint = "https://api.anthropic.com/messages"

        let responseJSON = """
        {
          "data": [
            { "id": "claude-3" },
            { "id": "  claude-2  " },
            { "id": null },
            { "id": "claude-2" }
          ]
        }
        """

        let models = try await withMockedHTTPResponses(
            handler: { req in
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(req.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(responseJSON.utf8))
            },
            {
                try await self.service.fetchAvailableModels(settings: settings)
            }
        )

        XCTAssertEqual(models, ["claude-2", "claude-3"])

        let captured = HTTPTestStubURLProtocol.recordedRequests()
        let request = try XCTUnwrap(captured.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/models")
    }
}
