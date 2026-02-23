import XCTest
@testable import SceneApp

@MainActor
final class AppStoreStoryGraphTests: XCTestCase {
    func testAddStoryGraphEdgeCreatesEdgeWithNormalizedWeight() throws {
        let (store, ids) = SceneTestFixtures.makeStoreFromFixture()
        let initialCount = store.project.storyGraphEdges.count

        let newEdgeID = store.addStoryGraphEdge(
            fromCompendiumID: ids.compendiumBodyEntryID,
            toCompendiumID: ids.compendiumTagEntryID,
            relation: .escalates,
            weight: 1.8,
            note: "world pressure rises"
        )

        let edgeID = try XCTUnwrap(newEdgeID)
        XCTAssertEqual(store.project.storyGraphEdges.count, initialCount + 1)

        let edge = try XCTUnwrap(store.project.storyGraphEdges.first(where: { $0.id == edgeID }))
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
}
