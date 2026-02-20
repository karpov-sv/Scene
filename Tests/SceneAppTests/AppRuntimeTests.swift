import XCTest
@testable import SceneApp

final class AppRuntimeTests: XCTestCase {
    func testRuntimeFlagsTrackUITestingMode() {
        XCTAssertEqual(AppRuntime.shouldRestoreOpenProjectSession, !AppRuntime.isUITesting)
        XCTAssertEqual(AppRuntime.shouldPersistOpenProjectSession, !AppRuntime.isUITesting)
        XCTAssertEqual(AppRuntime.shouldAutoDiscoverModels, !AppRuntime.isUITesting)
    }
}
