import Foundation

enum AppRuntime {
    static var isUITesting: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("--ui-testing") {
            return true
        }
        return processInfo.environment["SCENE_UI_TEST_MODE"] == "1"
    }

    static var shouldRestoreOpenProjectSession: Bool {
        !isUITesting
    }

    static var shouldPersistOpenProjectSession: Bool {
        !isUITesting
    }

    static var shouldAutoDiscoverModels: Bool {
        !isUITesting
    }
}
