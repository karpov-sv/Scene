import SwiftUI
import AppKit

final class SceneAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched from `swift run`, make the app frontmost so keyboard input
        // is delivered to the window instead of remaining in the terminal.
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct SceneApp: App {
    @NSApplicationDelegateAdaptor(SceneAppDelegate.self) private var appDelegate
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
