import XCTest
@testable import SceneApp

final class MentionParsingTests: XCTestCase {
    func testNormalizeCollapsesWhitespaceAndLowercases() {
        XCTAssertEqual(
            MentionParsing.normalize("  Alpha   BETA\tGamma  "),
            "alpha beta gamma"
        )
    }

    func testActiveQueryParsesInlineTagMention() throws {
        let text = "Talk to @alpha"
        let query = try XCTUnwrap(
            MentionParsing.activeQuery(in: text, caretLocation: (text as NSString).length)
        )

        XCTAssertEqual(query.trigger, .tag)
        XCTAssertEqual(query.query, "alpha")
        XCTAssertEqual((text as NSString).substring(with: query.tokenRange), "@alpha")
    }

    func testActiveQueryParsesBracketMentionWithoutClosingBracket() throws {
        let text = "Scene #[FinalShowdown"
        let query = try XCTUnwrap(
            MentionParsing.activeQuery(in: text, caretLocation: (text as NSString).length)
        )

        XCTAssertEqual(query.trigger, .scene)
        XCTAssertEqual(query.query, "FinalShowdown")
    }

    func testActiveQueryReturnsNilForClosedBracketToken() {
        let text = "Scene #[Final Showdown]"
        let query = MentionParsing.activeQuery(
            in: text,
            caretLocation: (text as NSString).length
        )
        XCTAssertNil(query)
    }

    func testReplacingTokenUpdatesTextAndRejectsInvalidRange() {
        let original = "hello @alpha"
        let valid = MentionParsing.replacingToken(
            in: original,
            range: NSRange(location: 6, length: 6),
            with: "@[Alpha Hero]"
        )
        XCTAssertEqual(valid, "hello @[Alpha Hero]")

        let invalid = MentionParsing.replacingToken(
            in: original,
            range: NSRange(location: 100, length: 1),
            with: "x"
        )
        XCTAssertNil(invalid)
    }

    func testExtractMentionTokensCollectsBracketAndInlineMentions() {
        let text = """
        @[Alpha Hero] meets @beta_2 in #scene-one.
        Then #[Scene Two] appears, while word@ignored and text#ignored do not.
        """

        let tokens = MentionParsing.extractMentionTokens(from: text)
        XCTAssertEqual(tokens.tags, Set(["alpha hero", "beta_2"]))
        XCTAssertEqual(tokens.scenes, Set(["scene-one", "scene two"]))
    }
}
