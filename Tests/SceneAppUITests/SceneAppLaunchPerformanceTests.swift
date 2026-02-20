import XCTest

final class SceneAppLaunchPerformanceTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments.append("--ui-testing")
            app.launchEnvironment["SCENE_UI_TEST_MODE"] = "1"
            app.launch()
            app.terminate()
        }
    }
}
