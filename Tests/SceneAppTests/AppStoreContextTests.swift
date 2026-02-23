import XCTest
@testable import SceneApp

@MainActor
final class AppStoreContextTests: XCTestCase {
    func testCompendiumContextSelectionDeduplicatesAndFiltersInvalidIDs() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()
        let invalidID = UUID()

        store.setCompendiumContextIDsForCurrentScene([
            ids.compendiumTitleEntryID,
            invalidID,
            ids.compendiumTitleEntryID
        ])

        XCTAssertEqual(store.selectedSceneContextCompendiumIDs, [ids.compendiumTitleEntryID])
    }

    func testSceneAndChapterContextGettersFilterEntriesWithoutSummaries() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        store.setSceneSummaryContextIDsForCurrentScene([ids.sceneOneID, ids.sceneTwoID])
        store.setChapterSummaryContextIDsForCurrentScene([ids.chapterOneID, ids.chapterTwoID])

        XCTAssertEqual(store.selectedSceneContextSceneSummaryIDs, [ids.sceneOneID])
        XCTAssertEqual(store.selectedSceneContextChapterSummaryIDs, [ids.chapterOneID])
    }

    func testClearCurrentSceneContextSelectionRemovesAllSelectionTypes() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        store.setCompendiumContextIDsForCurrentScene([ids.compendiumBodyEntryID])
        store.setSceneSummaryContextIDsForCurrentScene([ids.sceneOneID])
        store.setChapterSummaryContextIDsForCurrentScene([ids.chapterOneID])
        XCTAssertEqual(store.selectedSceneContextTotalCount, 3)

        store.clearCurrentSceneContextSelection()

        XCTAssertEqual(store.selectedSceneContextCompendiumIDs, [])
        XCTAssertEqual(store.selectedSceneContextSceneSummaryIDs, [])
        XCTAssertEqual(store.selectedSceneContextChapterSummaryIDs, [])
        XCTAssertEqual(store.selectedSceneContextTotalCount, 0)
    }

    func testWorkshopContextTogglesPersistPerSession() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        XCTAssertTrue(store.workshopUseSceneContext)
        XCTAssertFalse(store.workshopUseCompendiumContext)

        store.selectWorkshopSession(ids.workshopSessionTwoID)
        XCTAssertFalse(store.workshopUseSceneContext)
        XCTAssertTrue(store.workshopUseCompendiumContext)

        store.setWorkshopUseSceneContext(true)
        store.setWorkshopUseCompendiumContext(true)

        let updatedSessionTwo = try XCTUnwrap(
            store.project.workshopSessions.first(where: { $0.id == ids.workshopSessionTwoID })
        )
        XCTAssertTrue(updatedSessionTwo.useSceneContext)
        XCTAssertTrue(updatedSessionTwo.useCompendiumContext)

        store.selectWorkshopSession(ids.workshopSessionOneID)
        XCTAssertTrue(store.workshopUseSceneContext)
        XCTAssertFalse(store.workshopUseCompendiumContext)

        store.selectWorkshopSession(ids.workshopSessionTwoID)
        XCTAssertTrue(store.workshopUseSceneContext)
        XCTAssertTrue(store.workshopUseCompendiumContext)
    }

    func testScenePlanDraftPersistsIntoProjectStatePerScene() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()
        store.selectScene(ids.sceneOneID, chapterID: ids.chapterOneID)

        store.updateSelectedSceneProsePlanDraft("1. Enter station\n2. Spot courier")

        XCTAssertEqual(
            store.project.sceneProsePlanDraftByScene[ids.sceneOneID.uuidString],
            "1. Enter station\n2. Spot courier"
        )
        XCTAssertEqual(store.selectedSceneProsePlanDraft, "1. Enter station\n2. Spot courier")

        store.selectScene(ids.sceneTwoID, chapterID: ids.chapterOneID)
        XCTAssertEqual(store.selectedSceneProsePlanDraft, "")

        store.selectScene(ids.sceneOneID, chapterID: ids.chapterOneID)
        XCTAssertEqual(store.selectedSceneProsePlanDraft, "1. Enter station\n2. Spot courier")

        store.clearSelectedSceneProsePlanDraft()
        XCTAssertNil(store.project.sceneProsePlanDraftByScene[ids.sceneOneID.uuidString])
        XCTAssertEqual(store.selectedSceneProsePlanDraft, "")
    }
}
