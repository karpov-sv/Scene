import XCTest
@testable import SceneApp

@MainActor
final class AppHelpTests: XCTestCase {
    func testHomeTopicUsesHomeAnchorAndIndexPage() {
        XCTAssertEqual(AppHelp.Topic.home.anchor, "home")
        XCTAssertEqual(AppHelp.Topic.home.page, "index")
    }

    func testNonHomeTopicsUseAnchorAsPageAndAnchorsAreUnique() {
        let topics: [AppHelp.Topic] = [
            .workspace,
            .editor,
            .textGeneration,
            .rewriting,
            .compendium,
            .context,
            .mentions,
            .rollingMemory,
            .workshop,
            .checkpoints,
            .aiProviders,
            .promptTemplates,
            .importExport,
            .keyboardShortcuts
        ]

        for topic in topics {
            XCTAssertEqual(topic.page, topic.anchor)
        }

        let anchors = topics.map(\.anchor)
        XCTAssertEqual(Set(anchors).count, anchors.count)
    }
}
