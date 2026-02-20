import Foundation
@testable import SceneApp

struct SceneFixtureIDs {
    let chapterOneID: UUID
    let chapterTwoID: UUID
    let sceneOneID: UUID
    let sceneTwoID: UUID
    let sceneThreeID: UUID
    let compendiumTitleEntryID: UUID
    let compendiumBodyEntryID: UUID
    let compendiumTagEntryID: UUID
    let workshopSessionOneID: UUID
    let workshopSessionTwoID: UUID
}

enum SceneTestFixtures {
    static func makeProjectFixture() -> (project: StoryProject, ids: SceneFixtureIDs) {
        let chapterOneID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let chapterTwoID = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        let sceneOneID = UUID(uuidString: "00000000-0000-0000-0000-000000000911")!
        let sceneTwoID = UUID(uuidString: "00000000-0000-0000-0000-000000000912")!
        let sceneThreeID = UUID(uuidString: "00000000-0000-0000-0000-000000000913")!
        let compendiumTitleEntryID = UUID(uuidString: "00000000-0000-0000-0000-000000000921")!
        let compendiumBodyEntryID = UUID(uuidString: "00000000-0000-0000-0000-000000000922")!
        let compendiumTagEntryID = UUID(uuidString: "00000000-0000-0000-0000-000000000923")!
        let workshopSessionOneID = UUID(uuidString: "00000000-0000-0000-0000-000000000931")!
        let workshopSessionTwoID = UUID(uuidString: "00000000-0000-0000-0000-000000000932")!

        let chapterOne = Chapter(
            id: chapterOneID,
            title: "Chapter One",
            scenes: [
                Scene(
                    id: sceneOneID,
                    title: "Scene One",
                    content: "alpha one alpha",
                    summary: "scene alpha summary",
                    notes: "scene alpha note"
                ),
                Scene(
                    id: sceneTwoID,
                    title: "Scene Two",
                    content: "alpha two",
                    summary: "",
                    notes: "scene two note"
                ),
            ],
            summary: "chapter alpha summary",
            notes: "chapter alpha note"
        )

        let chapterTwo = Chapter(
            id: chapterTwoID,
            title: "Chapter Two",
            scenes: [
                Scene(
                    id: sceneThreeID,
                    title: "Scene Three",
                    content: "gamma",
                    summary: "scene three summary",
                    notes: "scene three note"
                ),
            ],
            summary: "",
            notes: "chapter two note"
        )

        let compendium: [CompendiumEntry] = [
            CompendiumEntry(
                id: compendiumTitleEntryID,
                category: .characters,
                title: "Alpha Hero",
                body: "unrelated body",
                tags: ["protagonist"]
            ),
            CompendiumEntry(
                id: compendiumBodyEntryID,
                category: .lore,
                title: "Body Entry",
                body: "alpha body detail",
                tags: ["world"]
            ),
            CompendiumEntry(
                id: compendiumTagEntryID,
                category: .notes,
                title: "Tagged Entry",
                body: "no match in body",
                tags: ["alphaTag"]
            ),
        ]

        let workshopSessionOne = WorkshopSession(
            id: workshopSessionOneID,
            name: "Session One",
            messages: [
                WorkshopMessage(role: .assistant, content: "hello one")
            ],
            useSceneContext: true,
            useCompendiumContext: false
        )
        let workshopSessionTwo = WorkshopSession(
            id: workshopSessionTwoID,
            name: "Session Two",
            messages: [
                WorkshopMessage(role: .assistant, content: "hello two")
            ],
            useSceneContext: false,
            useCompendiumContext: true
        )

        var settings = GenerationSettings.default
        settings.endpoint = ""
        settings.requestTimeoutSeconds = 1

        let project = StoryProject(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000900")!,
            title: "Fixture Project",
            metadata: .empty,
            notes: "project alpha note",
            autosaveEnabled: false,
            chapters: [chapterOne, chapterTwo],
            compendium: compendium,
            prompts: PromptTemplate.builtInTemplates,
            selectedSceneID: sceneOneID,
            selectedProsePromptID: PromptTemplate.defaultProseTemplate.id,
            selectedRewritePromptID: PromptTemplate.defaultRewriteTemplate.id,
            selectedSummaryPromptID: PromptTemplate.defaultSummaryTemplate.id,
            workshopSessions: [workshopSessionOne, workshopSessionTwo],
            selectedWorkshopSessionID: workshopSessionOneID,
            workshopInputHistoryBySession: [:],
            selectedWorkshopPromptID: PromptTemplate.defaultWorkshopTemplate.id,
            beatInputHistoryByScene: [:],
            sceneContextCompendiumSelection: [:],
            sceneContextSceneSummarySelection: [:],
            sceneContextChapterSummarySelection: [:],
            sceneNarrativeStates: [:],
            rollingWorkshopMemoryBySession: [:],
            rollingSceneMemoryByScene: [
                sceneTwoID.uuidString: RollingSceneMemory(summary: "scene memory", sourceContentHash: "hash")
            ],
            rollingChapterMemoryByChapter: [
                chapterOneID.uuidString: RollingChapterMemory(summary: "chapter memory", sourceFingerprint: "fingerprint")
            ],
            settings: settings,
            editorAppearance: .default,
            updatedAt: .now
        )

        let ids = SceneFixtureIDs(
            chapterOneID: chapterOneID,
            chapterTwoID: chapterTwoID,
            sceneOneID: sceneOneID,
            sceneTwoID: sceneTwoID,
            sceneThreeID: sceneThreeID,
            compendiumTitleEntryID: compendiumTitleEntryID,
            compendiumBodyEntryID: compendiumBodyEntryID,
            compendiumTagEntryID: compendiumTagEntryID,
            workshopSessionOneID: workshopSessionOneID,
            workshopSessionTwoID: workshopSessionTwoID
        )

        return (project, ids)
    }

    @MainActor
    static func makeStoreFromFixture() -> (store: AppStore, ids: SceneFixtureIDs) {
        let fixture = makeProjectFixture()
        let store = AppStore(documentProject: fixture.project, projectURL: nil)
        return (store, fixture.ids)
    }
}
