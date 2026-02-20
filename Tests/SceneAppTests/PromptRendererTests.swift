import XCTest
@testable import SceneApp

final class PromptRendererTests: XCTestCase {
    private let renderer = PromptRenderer()

    func testBlankTemplateUsesFallbackTemplate() {
        let context = PromptRenderer.Context(
            variables: ["PROJECT_TITLE": "My Project"]
        )

        let result = renderer.render(
            template: "   ",
            fallbackTemplate: "Title: {{project_title}}",
            context: context
        )

        XCTAssertEqual(result.renderedText, "Title: My Project")
        XCTAssertEqual(result.warnings, [])
    }

    func testCanonicalAndLegacyVariablesRenderFromResolvedContext() {
        let context = PromptRenderer.Context(
            variables: ["PROJECT_TITLE": "My Project"]
        )

        let result = renderer.render(
            template: "{{project_title}} / {project_title}",
            context: context
        )

        XCTAssertEqual(result.renderedText, "My Project / My Project")
    }

    func testChatHistoryUsesConversationTurnsAndLimit() {
        let context = PromptRenderer.Context(
            conversationTurns: [
                .init(roleLabel: "User", content: "First"),
                .init(roleLabel: "Assistant", content: "Second"),
                .init(roleLabel: "User", content: "Third")
            ]
        )

        let result = renderer.render(
            template: "{{chat_history(turns=2)}}",
            context: context
        )

        XCTAssertEqual(result.renderedText, "Assistant: Second\n\nUser: Third")
    }

    func testChatHistoryFallsBackToConversationVariableWhenNoTurnsProvided() {
        let context = PromptRenderer.Context(
            variables: ["conversation": "Assistant: Existing"]
        )

        let result = renderer.render(
            template: "{{chat_history(turns=3)}}",
            context: context
        )

        XCTAssertEqual(result.renderedText, "Assistant: Existing")
    }

    func testContextAndSceneFunctionsRespectLimits() {
        let context = PromptRenderer.Context(
            sceneFullText: "abcdef",
            contextSections: [
                "context": "123456",
                "context_compendium": "COMPENDIUM",
                "context_rolling": "ROLLING"
            ]
        )

        let result = renderer.render(
            template: "{{scene_tail(chars=4)}}|{{context(max_chars='3')}}|{{context_compendium(max_chars=4)}}|{{rolling_summary(max_chars=2)}}",
            context: context
        )

        XCTAssertEqual(result.renderedText, "cdef|123|COMP|RO")
    }

    func testInvalidNumericArgumentsProduceWarningsAndFallbackBehavior() {
        let context = PromptRenderer.Context(
            sceneFullText: "abcdef",
            contextSections: ["context": "abcdef"]
        )

        let result = renderer.render(
            template: "{{scene_tail(chars=abc)}}|{{scene_tail(chars=-2)}}|{{context(max_chars=-1)}}|{{context(max_chars=oops)}}",
            context: context
        )

        XCTAssertEqual(result.renderedText, "abcdef|||abcdef")
        XCTAssertEqual(result.warnings.count, 4)
        XCTAssertTrue(result.warnings.contains { $0.contains("Invalid `chars` value `abc`") })
        XCTAssertTrue(result.warnings.contains { $0.contains("must be >= 0") })
        XCTAssertTrue(result.warnings.contains { $0.contains("Invalid `max_chars` value `oops`") })
    }

    func testUnknownVariableAndFunctionWarningsAreDeduplicated() {
        let context = PromptRenderer.Context()

        let result = renderer.render(
            template: "{{missing}} {{missing}} {{unknown_fn()}} {{unknown_fn()}}",
            context: context
        )

        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertTrue(result.warnings.contains("Unknown template variable `{{missing}}`."))
        XCTAssertTrue(result.warnings.contains("Unknown template function `{{unknown_fn(...)}}`."))
    }
}
