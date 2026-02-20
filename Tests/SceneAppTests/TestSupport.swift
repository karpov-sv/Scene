import Foundation
import XCTest
@testable import SceneApp

func withTemporaryDirectory<T>(
    prefix: String = "SceneTests",
    _ body: (URL) throws -> T
) throws -> T {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: root)
    }
    return try body(root)
}

func makeIsolatedPersistence() -> (persistence: ProjectPersistence, defaults: UserDefaults, suiteName: String) {
    let suiteName = "SceneAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    let persistence = ProjectPersistence(fileManager: .default, userDefaults: defaults)
    return (persistence, defaults, suiteName)
}

func assertNoResult(
    _ results: [AppStore.GlobalSearchResult],
    kind: AppStore.GlobalSearchResult.Kind,
    sceneID: UUID?
) {
    XCTAssertFalse(
        results.contains { result in
            result.kind == kind && result.sceneID == sceneID
        }
    )
}
