import XCTest
@testable import SceneApp

@MainActor
final class AppStoreSearchReplaceTests: XCTestCase {
    func testSceneScopeSearchReturnsOnlySelectedSceneMatches() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        store.globalSearchScope = .scene
        store.globalSearchQuery = "alpha"
        store.refreshGlobalSearchResults()

        XCTAssertFalse(store.globalSearchResults.isEmpty)
        XCTAssertTrue(
            store.globalSearchResults.allSatisfy { result in
                result.kind == .scene && result.sceneID == ids.sceneOneID
            }
        )
    }

    func testReplaceCurrentMatchInSelectedSceneQueuesEditorRequest() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        store.globalSearchScope = .project
        store.globalSearchQuery = "alpha"
        store.refreshGlobalSearchResults()

        let result = try XCTUnwrap(
            store.globalSearchResults.first { $0.kind == .scene && $0.sceneID == ids.sceneOneID }
        )
        store.setSelectedGlobalSearchResultID(result.id)

        XCTAssertTrue(store.replaceCurrentSearchMatch(with: "beta"))

        let pending = try XCTUnwrap(store.pendingSceneReplace)
        XCTAssertEqual(pending.sceneID, ids.sceneOneID)
        XCTAssertEqual(pending.query, "alpha")
        XCTAssertEqual(pending.replacement, "beta")
        XCTAssertEqual(pending.location, result.location)
        XCTAssertEqual(pending.length, result.length)

        let selectedScene = try XCTUnwrap(
            store.project.chapters.flatMap(\.scenes).first(where: { $0.id == ids.sceneOneID })
        )
        XCTAssertEqual(selectedScene.content, "alpha one alpha")
    }

    func testReplaceCurrentMatchInNonSelectedSceneMutatesAndInvalidatesRollingMemory() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        store.globalSearchScope = .project
        store.globalSearchQuery = "alpha"
        store.refreshGlobalSearchResults()

        let result = try XCTUnwrap(
            store.globalSearchResults.first { $0.kind == .scene && $0.sceneID == ids.sceneTwoID }
        )
        store.setSelectedGlobalSearchResultID(result.id)

        XCTAssertTrue(store.replaceCurrentSearchMatch(with: "beta"))

        let updatedScene = try XCTUnwrap(
            store.project.chapters.flatMap(\.scenes).first(where: { $0.id == ids.sceneTwoID })
        )
        XCTAssertEqual(updatedScene.content, "beta two")
        XCTAssertNil(store.project.rollingSceneMemoryByScene[ids.sceneTwoID.uuidString])
        XCTAssertNil(store.project.rollingChapterMemoryByChapter[ids.chapterOneID.uuidString])
    }

    func testReplaceCurrentMatchInCompendiumTitle() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        store.globalSearchScope = .compendium
        store.globalSearchQuery = "alpha"
        store.refreshGlobalSearchResults()

        let result = try XCTUnwrap(
            store.globalSearchResults.first { result in
                result.kind == .compendium &&
                    result.compendiumEntryID == ids.compendiumTitleEntryID &&
                    result.isCompendiumTitleMatch
            }
        )
        store.setSelectedGlobalSearchResultID(result.id)

        XCTAssertTrue(store.replaceCurrentSearchMatch(with: "Beta"))

        let entry = try XCTUnwrap(
            store.project.compendium.first(where: { $0.id == ids.compendiumTitleEntryID })
        )
        XCTAssertEqual(entry.title, "Beta Hero")
    }

    func testReplaceCurrentMatchInCompendiumTagsReturnsFalse() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        store.globalSearchScope = .compendium
        store.globalSearchQuery = "alpha"
        store.refreshGlobalSearchResults()

        let tagResult = try XCTUnwrap(
            store.globalSearchResults.first { result in
                result.kind == .compendium &&
                    result.compendiumEntryID == ids.compendiumTagEntryID &&
                    result.location == nil
            }
        )
        store.setSelectedGlobalSearchResultID(tagResult.id)

        XCTAssertFalse(store.replaceCurrentSearchMatch(with: "Beta"))

        let entry = try XCTUnwrap(
            store.project.compendium.first(where: { $0.id == ids.compendiumTagEntryID })
        )
        XCTAssertEqual(entry.tags, ["alphaTag"])
    }

    func testReplaceAllForSceneQueuesPendingRequestAndCountsMatches() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        store.globalSearchScope = .scene
        store.globalSearchQuery = "alpha"

        let count = store.replaceAllSearchMatches(with: "beta")
        XCTAssertEqual(count, 2)

        let pending = try XCTUnwrap(store.pendingSceneReplaceAll)
        XCTAssertEqual(pending.sceneID, ids.sceneOneID)
        XCTAssertEqual(pending.query, "alpha")
        XCTAssertEqual(pending.replacement, "beta")

        let selectedScene = try XCTUnwrap(
            store.project.chapters.flatMap(\.scenes).first(where: { $0.id == ids.sceneOneID })
        )
        XCTAssertEqual(selectedScene.content, "alpha one alpha")
    }

    func testReplaceAllForProjectMutatesNonSelectedSceneAndQueuesSelectedScene() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        store.globalSearchScope = .project
        store.globalSearchQuery = "alpha"

        let count = store.replaceAllSearchMatches(with: "beta")
        XCTAssertEqual(count, 3)

        let pending = try XCTUnwrap(store.pendingSceneReplaceAll)
        XCTAssertEqual(pending.sceneID, ids.sceneOneID)

        let secondScene = try XCTUnwrap(
            store.project.chapters.flatMap(\.scenes).first(where: { $0.id == ids.sceneTwoID })
        )
        XCTAssertEqual(secondScene.content, "beta two")
    }

    func testDidCompleteEditorReplaceAllRefreshesAfterEditorMutation() throws {
        let (store, _) = SceneTestFixtures.makeStoreFromFixture()

        store.globalSearchScope = .scene
        store.globalSearchQuery = "alpha"
        XCTAssertEqual(store.replaceAllSearchMatches(with: "beta"), 2)

        store.updateSelectedSceneContent("beta one beta")
        store.didCompleteEditorReplaceAll(count: 2)

        XCTAssertEqual(store.globalSearchResults.count, 0)
    }

    func testDidCompleteEditorReplaceRefreshesAndSelectsNextMatch() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        store.globalSearchScope = .scene
        store.globalSearchQuery = "alpha"
        store.refreshGlobalSearchResults()
        let initial = try XCTUnwrap(store.globalSearchResults.first)
        store.setSelectedGlobalSearchResultID(initial.id)

        store.updateSelectedSceneContent("beta one alpha")
        store.didCompleteEditorReplace()

        XCTAssertEqual(store.globalSearchResults.count, 1)
        let selected = try XCTUnwrap(store.selectedGlobalSearchResult())
        XCTAssertEqual(selected.kind, .scene)
        XCTAssertEqual(selected.sceneID, ids.sceneOneID)
        XCTAssertEqual(selected.location, 9)
    }
}
