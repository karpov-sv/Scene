import UniformTypeIdentifiers
import XCTest
@testable import SceneApp

final class SceneProjectDocumentTests: XCTestCase {
    func testSceneProjectUTTypeIdentifier() {
        XCTAssertEqual(UTType.sceneProject.identifier, "com.karpov.scene.project")
    }

    func testSnapshotReturnsCurrentProject() throws {
        let document = SceneProjectDocument()
        let snapshot = try document.snapshot(contentType: .sceneProject)

        XCTAssertEqual(snapshot.id, document.project.id)
        XCTAssertEqual(snapshot.title, document.project.title)
    }
}
