import SwiftUI

@main
struct SceneApp: App {
    @StateObject private var store = AppStore()

    var body: some SwiftUI.Scene {
        WindowGroup("Scene") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1200, minHeight: 760)
        }
        .windowResizability(.contentMinSize)
    }
}
