import XCTest
@testable import SceneApp

@MainActor
final class AppStorePerformanceTests: XCTestCase {
    func testReplaceAllProjectScopePerformance() {
        let repeatedChunk = Array(repeating: "alpha line", count: 6000).joined(separator: "\n")

        measure {
            var fixture = SceneTestFixtures.makeProjectFixture()
            fixture.project.chapters[0].scenes[1].content = repeatedChunk

            let store = AppStore(documentProject: fixture.project, projectURL: nil)
            store.globalSearchScope = .project
            store.globalSearchQuery = "alpha"
            _ = store.replaceAllSearchMatches(with: "beta")
        }
    }
}
