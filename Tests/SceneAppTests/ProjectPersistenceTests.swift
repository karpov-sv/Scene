import XCTest
@testable import SceneApp

final class ProjectPersistenceTests: XCTestCase {
    func testNormalizeProjectURLAppendsSceneprojExtension() {
        let (persistence, defaults, suiteName) = makeIsolatedPersistence()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let input = URL(fileURLWithPath: "/tmp/MyProject")
        let normalized = persistence.normalizeProjectURL(input)
        XCTAssertEqual(normalized.pathExtension, ProjectPersistence.projectDirectoryExtension)
    }

    func testSaveAndLoadProjectRoundTripPreservesStructuredData() throws {
        let (persistence, defaults, suiteName) = makeIsolatedPersistence()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var fixture = SceneTestFixtures.makeProjectFixture()
        fixture.project.sceneContextCompendiumSelection = [
            fixture.ids.sceneOneID.uuidString: [fixture.ids.compendiumBodyEntryID]
        ]
        fixture.project.sceneContextSceneSummarySelection = [
            fixture.ids.sceneOneID.uuidString: [fixture.ids.sceneOneID]
        ]
        fixture.project.sceneContextChapterSummarySelection = [
            fixture.ids.sceneOneID.uuidString: [fixture.ids.chapterOneID]
        ]

        try withTemporaryDirectory { root in
            let projectURL = root.appendingPathComponent("RoundTripProject")
            let savedURL = try persistence.saveProject(fixture.project, at: projectURL)
            let loaded = try persistence.loadProject(at: savedURL)

            XCTAssertEqual(loaded.title, fixture.project.title)
            XCTAssertEqual(loaded.notes, fixture.project.notes)
            XCTAssertEqual(loaded.chapters.map(\.title), fixture.project.chapters.map(\.title))
            XCTAssertEqual(loaded.chapters.flatMap(\.scenes).map(\.content), fixture.project.chapters.flatMap(\.scenes).map(\.content))
            XCTAssertEqual(loaded.compendium.count, fixture.project.compendium.count)
            for (loadedEntry, fixtureEntry) in zip(loaded.compendium, fixture.project.compendium) {
                XCTAssertEqual(loadedEntry.id, fixtureEntry.id)
                XCTAssertEqual(loadedEntry.category, fixtureEntry.category)
                XCTAssertEqual(loadedEntry.title, fixtureEntry.title)
                XCTAssertEqual(loadedEntry.body, fixtureEntry.body)
                XCTAssertEqual(loadedEntry.tags, fixtureEntry.tags)
            }
            XCTAssertEqual(loaded.sceneContextCompendiumSelection, fixture.project.sceneContextCompendiumSelection)
            XCTAssertEqual(loaded.sceneContextSceneSummarySelection, fixture.project.sceneContextSceneSummarySelection)
            XCTAssertEqual(loaded.sceneContextChapterSummarySelection, fixture.project.sceneContextChapterSummarySelection)
            XCTAssertEqual(loaded.workshopSessions.count, fixture.project.workshopSessions.count)
            for (loadedSession, fixtureSession) in zip(loaded.workshopSessions, fixture.project.workshopSessions) {
                XCTAssertEqual(loadedSession.id, fixtureSession.id)
                XCTAssertEqual(loadedSession.useSceneContext, fixtureSession.useSceneContext)
                XCTAssertEqual(loadedSession.useCompendiumContext, fixtureSession.useCompendiumContext)
            }
            XCTAssertEqual(
                Set(loaded.rollingSceneMemoryByScene.keys),
                Set(fixture.project.rollingSceneMemoryByScene.keys)
            )
            for key in fixture.project.rollingSceneMemoryByScene.keys {
                let loadedMemory = try XCTUnwrap(loaded.rollingSceneMemoryByScene[key])
                let fixtureMemory = try XCTUnwrap(fixture.project.rollingSceneMemoryByScene[key])
                XCTAssertEqual(loadedMemory.summary, fixtureMemory.summary)
                XCTAssertEqual(loadedMemory.sourceContentHash, fixtureMemory.sourceContentHash)
            }

            XCTAssertEqual(
                Set(loaded.rollingChapterMemoryByChapter.keys),
                Set(fixture.project.rollingChapterMemoryByChapter.keys)
            )
            for key in fixture.project.rollingChapterMemoryByChapter.keys {
                let loadedMemory = try XCTUnwrap(loaded.rollingChapterMemoryByChapter[key])
                let fixtureMemory = try XCTUnwrap(fixture.project.rollingChapterMemoryByChapter[key])
                XCTAssertEqual(loadedMemory.summary, fixtureMemory.summary)
                XCTAssertEqual(loadedMemory.sourceFingerprint, fixtureMemory.sourceFingerprint)
            }
        }
    }

    func testLoadLastOpenedProjectURLsFiltersMissingAndDuplicatePaths() throws {
        let (persistence, defaults, suiteName) = makeIsolatedPersistence()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let fixture = SceneTestFixtures.makeProjectFixture()

        try withTemporaryDirectory { root in
            let projectOne = try persistence.saveProject(
                fixture.project,
                at: root.appendingPathComponent("ProjectOne")
            )
            let projectTwo = try persistence.saveProject(
                fixture.project,
                at: root.appendingPathComponent("ProjectTwo")
            )
            let missing = root
                .appendingPathComponent("Missing")
                .appendingPathExtension(ProjectPersistence.projectDirectoryExtension)

            persistence.saveLastOpenedProjectURLs([projectOne, projectOne, missing, projectTwo])
            let loaded = persistence.loadLastOpenedProjectURLs()

            XCTAssertEqual(loaded.map(\.path), [projectOne.path, projectTwo.path])
            XCTAssertEqual(persistence.loadLastOpenedProjectURL()?.path, projectOne.path)
        }
    }

    func testResolveExistingProjectURLFindsProjectWhenExtensionWasOmitted() throws {
        let (persistence, defaults, suiteName) = makeIsolatedPersistence()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let fixture = SceneTestFixtures.makeProjectFixture()
        try withTemporaryDirectory { root in
            let baseURL = root.appendingPathComponent("NoExtensionProject")
            let saved = try persistence.saveProject(fixture.project, at: baseURL)
            let resolved = try persistence.resolveExistingProjectURL(baseURL)
            XCTAssertEqual(resolved.standardizedFileURL, saved.standardizedFileURL)
        }
    }

    func testSaveProjectRejectsDuplicateSceneIdentifiers() throws {
        let (persistence, defaults, suiteName) = makeIsolatedPersistence()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var fixture = SceneTestFixtures.makeProjectFixture()
        fixture.project.chapters[0].scenes[1].id = fixture.project.chapters[0].scenes[0].id

        try withTemporaryDirectory { root in
            XCTAssertThrowsError(
                try persistence.saveProject(
                    fixture.project,
                    at: root.appendingPathComponent("DuplicateSceneIDs")
                )
            ) { error in
                guard case ProjectPersistenceError.duplicateIdentifier(let details) = error else {
                    XCTFail("Expected duplicateIdentifier error, got \(error)")
                    return
                }
                XCTAssertTrue(details.contains("scene"))
            }
        }
    }
}
