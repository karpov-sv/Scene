import XCTest
@testable import SceneApp

@MainActor
final class AppStoreStoryGraphTests: XCTestCase {
    func testAddStoryGraphEdgeCreatesEdgeWithNormalizedWeight() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()
        let initialCount = store.project.storyGraphEdges.count

        let newEdgeID = store.addStoryGraphEdge(
            sceneID: ids.sceneOneID,
            fromCompendiumID: ids.compendiumBodyEntryID,
            toCompendiumID: ids.compendiumTagEntryID,
            relation: .escalates,
            weight: 1.8,
            note: "world pressure rises"
        )

        let edgeID = try XCTUnwrap(newEdgeID)
        XCTAssertEqual(store.project.storyGraphEdges.count, initialCount + 1)

        let edge = try XCTUnwrap(store.project.storyGraphEdges.first(where: { $0.id == edgeID }))
        XCTAssertEqual(edge.sceneID, ids.sceneOneID)
        XCTAssertEqual(edge.fromCompendiumID, ids.compendiumBodyEntryID)
        XCTAssertEqual(edge.toCompendiumID, ids.compendiumTagEntryID)
        XCTAssertEqual(edge.relation, .escalates)
        XCTAssertEqual(edge.weight, 1.0, accuracy: 0.0001)
        XCTAssertEqual(edge.note, "world pressure rises")
    }

    func testAddStoryGraphEdgeRejectsSelfLoop() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()
        let initialCount = store.project.storyGraphEdges.count

        let edgeID = store.addStoryGraphEdge(
            sceneID: ids.sceneOneID,
            fromCompendiumID: ids.compendiumTitleEntryID,
            toCompendiumID: ids.compendiumTitleEntryID,
            relation: .causes
        )

        XCTAssertNil(edgeID)
        XCTAssertEqual(store.project.storyGraphEdges.count, initialCount)
    }

    func testUpdateStoryGraphEdgeMutatesEndpointsAndProperties() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()
        let edgeID = try XCTUnwrap(store.project.storyGraphEdges.first?.id)

        store.updateStoryGraphEdgeRelation(edgeID, relation: .blocks)
        store.updateStoryGraphEdgeWeight(edgeID, weight: -0.5)
        store.updateStoryGraphEdgeNote(edgeID, note: "blocked by duty")
        store.updateStoryGraphEdgeEndpoints(
            edgeID,
            fromCompendiumID: ids.compendiumTagEntryID,
            toCompendiumID: ids.compendiumBodyEntryID
        )

        let edge = try XCTUnwrap(store.project.storyGraphEdges.first(where: { $0.id == edgeID }))
        XCTAssertEqual(edge.sceneID, ids.sceneOneID)
        XCTAssertEqual(edge.relation, .blocks)
        XCTAssertEqual(edge.weight, 0.0, accuracy: 0.0001)
        XCTAssertEqual(edge.note, "blocked by duty")
        XCTAssertEqual(edge.fromCompendiumID, ids.compendiumTagEntryID)
        XCTAssertEqual(edge.toCompendiumID, ids.compendiumBodyEntryID)
    }

    func testDeleteSelectedCompendiumEntryRemovesLinkedStoryGraphEdges() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()
        XCTAssertTrue(store.project.storyGraphEdges.contains { $0.fromCompendiumID == ids.compendiumTitleEntryID })

        store.selectCompendiumEntry(ids.compendiumTitleEntryID)
        store.deleteSelectedCompendiumEntry()

        XCTAssertFalse(
            store.project.storyGraphEdges.contains { edge in
                edge.fromCompendiumID == ids.compendiumTitleEntryID
                    || edge.toCompendiumID == ids.compendiumTitleEntryID
            }
        )
    }

    func testStoryGraphEdgesAreScopedByScene() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()

        _ = store.addStoryGraphEdge(
            sceneID: ids.sceneTwoID,
            fromCompendiumID: ids.compendiumBodyEntryID,
            toCompendiumID: ids.compendiumTagEntryID,
            relation: .escalates
        )

        let sceneOneEdges = store.storyGraphEdges(for: ids.sceneOneID)
        let sceneTwoEdges = store.storyGraphEdges(for: ids.sceneTwoID)

        XCTAssertEqual(sceneOneEdges.count, 1)
        XCTAssertEqual(sceneTwoEdges.count, 1)
        XCTAssertTrue(sceneOneEdges.allSatisfy { $0.sceneID == ids.sceneOneID })
        XCTAssertTrue(sceneTwoEdges.allSatisfy { $0.sceneID == ids.sceneTwoID })
    }
}
