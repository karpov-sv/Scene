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
        Window("Scene", id: "main-window") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1200, minHeight: 760)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project...") {
                    createProjectFromDialog()
                }
                .keyboardShortcut("n")

                Button("Open Project...") {
                    openProjectFromDialog()
                }
                .keyboardShortcut("o")
            }

            CommandMenu("Project") {
                Button("New Project...") {
                    createProjectFromDialog()
                }

                Button("Open Project...") {
                    openProjectFromDialog()
                }

                Divider()

                Button("Duplicate Project...") {
                    duplicateProjectFromDialog()
                }
                .disabled(!store.isProjectOpen)

                Button("Close Project") {
                    store.closeProject()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!store.isProjectOpen)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    store.showingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(!store.isProjectOpen)
            }
        }
    }

    private func createProjectFromDialog() {
        let suggestedName = store.isProjectOpen ? store.project.title : "Untitled"
        guard let destinationURL = ProjectDialogs.chooseNewProjectURL(suggestedName: suggestedName) else {
            return
        }

        do {
            try store.createNewProject(at: destinationURL)
        } catch {
            store.lastError = "Failed to create project: \(error.localizedDescription)"
        }
    }

    private func openProjectFromDialog() {
        guard let selectedURL = ProjectDialogs.chooseExistingProjectURL() else {
            return
        }

        do {
            try store.openProject(at: selectedURL)
        } catch {
            store.lastError = "Failed to open project: \(error.localizedDescription)"
        }
    }

    private func duplicateProjectFromDialog() {
        guard store.isProjectOpen else { return }

        let baseName = "\(store.currentProjectName) Copy"
        guard let destinationURL = ProjectDialogs.chooseDuplicateDestinationURL(defaultName: baseName) else {
            return
        }

        do {
            try store.duplicateCurrentProject(to: destinationURL)
        } catch {
            store.lastError = "Failed to duplicate project: \(error.localizedDescription)"
        }
    }
}
