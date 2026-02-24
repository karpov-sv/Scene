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

    func testProseOutputHintsAndPresetsAreMutuallyExclusive() throws {
        let (store, _) = SceneTestFixtures.makeStoreFromFixture()

        store.updateProseOutputTone(.tense)
        XCTAssertEqual(store.project.settings.proseOutputTone, .tense)
        XCTAssertEqual(store.project.settings.proseOutputToneCustom, "")

        store.updateProseOutputToneCustom("restrained, distant, quietly ominous")
        XCTAssertEqual(store.project.settings.proseOutputTone, .automatic)
        XCTAssertEqual(store.project.settings.proseOutputToneCustom, "restrained, distant, quietly ominous")

        store.updateProseOutputTone(.warm)
        XCTAssertEqual(store.project.settings.proseOutputTone, .warm)
        XCTAssertEqual(store.project.settings.proseOutputToneCustom, "")

        store.updateProseOutputStyle(.cinematic)
        XCTAssertEqual(store.project.settings.proseOutputStyle, .cinematic)
        XCTAssertEqual(store.project.settings.proseOutputStyleCustom, "")

        store.updateProseOutputStyleCustom("short clauses, heavy sensory detail")
        XCTAssertEqual(store.project.settings.proseOutputStyle, .automatic)
        XCTAssertEqual(store.project.settings.proseOutputStyleCustom, "short clauses, heavy sensory detail")

        store.updateProseOutputStyle(.minimalist)
        XCTAssertEqual(store.project.settings.proseOutputStyle, .minimalist)
        XCTAssertEqual(store.project.settings.proseOutputStyleCustom, "")
    }

    func testSelectedSceneProseOutputProfileUsesSceneOverridesAndResetFallsBackToDefaults() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()
        store.selectScene(ids.sceneOneID, chapterID: ids.chapterOneID)

        let defaultTemperature = store.project.settings.temperature
        XCTAssertEqual(store.selectedSceneProseOutputTone, store.project.settings.proseOutputTone)
        XCTAssertEqual(store.selectedSceneProseOutputTemperature, defaultTemperature, accuracy: 0.0001)

        store.updateSelectedSceneProseOutputTone(.tense)
        store.updateSelectedSceneProseOutputStyleCustom("choppy and jagged")
        store.updateSelectedSceneProseOutputLength(.short)
        store.updateSelectedSceneProseOutputTemperature(1.25)

        XCTAssertEqual(store.selectedSceneProseOutputTone, .tense)
        XCTAssertEqual(store.selectedSceneProseOutputStyle, .automatic)
        XCTAssertEqual(store.selectedSceneProseOutputStyleCustom, "choppy and jagged")
        XCTAssertEqual(store.selectedSceneProseOutputLength, .short)
        XCTAssertEqual(store.selectedSceneProseOutputTemperature, 1.25, accuracy: 0.0001)
        XCTAssertNotNil(store.project.sceneProseOutputProfileByScene[ids.sceneOneID.uuidString])

        store.selectScene(ids.sceneTwoID, chapterID: ids.chapterOneID)
        XCTAssertEqual(store.selectedSceneProseOutputTone, store.project.settings.proseOutputTone)
        XCTAssertEqual(store.selectedSceneProseOutputStyleCustom, store.project.settings.proseOutputStyleCustom)
        XCTAssertEqual(store.selectedSceneProseOutputLength, store.project.settings.proseOutputLength)
        XCTAssertEqual(store.selectedSceneProseOutputTemperature, defaultTemperature, accuracy: 0.0001)

        store.selectScene(ids.sceneOneID, chapterID: ids.chapterOneID)
        store.resetSelectedSceneProseOutputProfile()
        XCTAssertNil(store.project.sceneProseOutputProfileByScene[ids.sceneOneID.uuidString])
        XCTAssertEqual(store.selectedSceneProseOutputTone, store.project.settings.proseOutputTone)
        XCTAssertEqual(store.selectedSceneProseOutputStyleCustom, store.project.settings.proseOutputStyleCustom)
        XCTAssertEqual(store.selectedSceneProseOutputLength, store.project.settings.proseOutputLength)
        XCTAssertEqual(store.selectedSceneProseOutputTemperature, defaultTemperature, accuracy: 0.0001)
    }
}
