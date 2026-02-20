import Foundation
import XCTest
@testable import SceneApp

final class OpenAICompatibleAIServiceTests: XCTestCase {
    private let service = OpenAICompatibleAIService()

    func testMakeChatRequestPreviewBuildsNormalizedURLAndHeaders() throws {
        var settings = GenerationSettings.default
        settings.provider = .openAICompatible
        settings.endpoint = "https://example.com/models"
        settings.apiKey = "secret"
        settings.enableStreaming = true

        let request = TextGenerationRequest(
            systemPrompt: "sys",
            userPrompt: "user",
            model: "gpt-test",
            temperature: 0.4,
            maxTokens: 128
        )

        let preview = try service.makeChatRequestPreview(request: request, settings: settings)
        XCTAssertEqual(preview.url, "https://example.com/v1/chat/completions")
        XCTAssertEqual(preview.method, "POST")
        XCTAssertTrue(preview.headers.contains { $0.name == "Content-Type" && $0.value == "application/json" })
        XCTAssertTrue(preview.headers.contains { $0.name == "Authorization" && $0.value == "Bearer secret" })
        XCTAssertTrue(preview.bodyJSON.contains("\"stream\" : true"))
        XCTAssertTrue(preview.bodyHumanReadable.contains("messages:"))
    }

    func testGenerateTextResultParsesCompletionAndUsage() async throws {
        var settings = GenerationSettings.default
        settings.provider = .openAICompatible
        settings.endpoint = "https://example.com/v1"
        settings.apiKey = "secret"
        settings.enableStreaming = false

        let request = TextGenerationRequest(
            systemPrompt: "sys",
            userPrompt: "user",
            model: "gpt-test",
            temperature: 0.7,
            maxTokens: 256
        )

        let responseJSON = """
        {
          "choices": [
            { "message": { "role": "assistant", "content": "  hello world  " } }
          ],
          "usage": {
            "prompt_tokens": 11,
            "completion_tokens": 7,
            "total_tokens": 18
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
        XCTAssertEqual(result.usage, TokenUsage(promptTokens: 11, completionTokens: 7, totalTokens: 18))

        let captured = HTTPTestStubURLProtocol.recordedRequests()
        let sentRequest = try XCTUnwrap(captured.first)
        XCTAssertEqual(sentRequest.httpMethod, "POST")
        XCTAssertEqual(sentRequest.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testGenerateTextResultSurfacesProviderErrorOnHTTPFailure() async {
        var settings = GenerationSettings.default
        settings.provider = .openAICompatible
        settings.endpoint = "https://example.com/v1"
        settings.enableStreaming = false

        let request = TextGenerationRequest(
            systemPrompt: "sys",
            userPrompt: "user",
            model: "gpt-test",
            temperature: 0.7,
            maxTokens: 256
        )

        let responseJSON = #"{"error":{"message":"bad key"}}"#

        do {
            _ = try await withMockedHTTPResponses(
                handler: { req in
                    let response = HTTPURLResponse(
                        url: try XCTUnwrap(req.url),
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    return (response, Data(responseJSON.utf8))
                },
                {
                    try await self.service.generateTextResult(request, settings: settings, onPartial: nil)
                }
            )
            XCTFail("Expected requestFailed error")
        } catch let error as AIServiceError {
            guard case .requestFailed(let message) = error else {
                XCTFail("Expected requestFailed, got \(error)")
                return
            }
            XCTAssertEqual(message, "bad key")
        } catch {
            XCTFail("Expected AIServiceError, got \(error)")
        }
    }

    func testFetchAvailableModelsReturnsSortedUniqueIDs() async throws {
        var settings = GenerationSettings.default
        settings.provider = .openAICompatible
        settings.endpoint = "https://example.com/chat/completions"

        let responseJSON = """
        {
          "data": [
            { "id": "model-z" },
            { "id": "model-a" },
            { "id": "model-a" }
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

        XCTAssertEqual(models, ["model-a", "model-z"])

        let captured = HTTPTestStubURLProtocol.recordedRequests()
        let request = try XCTUnwrap(captured.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
    }

    func testFetchAvailableModelsSurfacesProviderMessage() async {
        var settings = GenerationSettings.default
        settings.provider = .openAICompatible
        settings.endpoint = "https://example.com/v1"

        do {
            _ = try await withMockedHTTPResponses(
                handler: { req in
                    let response = HTTPURLResponse(
                        url: try XCTUnwrap(req.url),
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    return (response, Data(#"{"error":{"message":"temporarily unavailable"}}"#.utf8))
                },
                {
                    try await self.service.fetchAvailableModels(settings: settings)
                }
            )
            XCTFail("Expected requestFailed error")
        } catch let error as AIServiceError {
            guard case .requestFailed(let message) = error else {
                XCTFail("Expected requestFailed, got \(error)")
                return
            }
            XCTAssertEqual(message, "temporarily unavailable")
        } catch {
            XCTFail("Expected AIServiceError, got \(error)")
        }
    }
}
