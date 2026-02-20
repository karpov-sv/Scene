import SwiftUI
import AppKit

@MainActor
final class SceneAppDelegate: NSObject, NSApplicationDelegate {
    private let persistence = ProjectPersistence.shared
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the help book bundled in Resources/SceneHelp.help so that
        // NSHelpManager.openHelpAnchor can find it. Without this, macOS falls
        // back to the Tips app for any help request.
        NSHelpManager.shared.registerBooks(in: Bundle.main)

        // When launched from `swift run`, make the app frontmost so keyboard input
        // is delivered to the window instead of remaining in the terminal.
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if AppRuntime.shouldRestoreOpenProjectSession {
                self.restoreLastProjectOrCreateUntitled()
            } else {
                self.openUntitledDocumentIfNeeded()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if AppRuntime.shouldPersistOpenProjectSession {
            persistOpenDocumentSession()
        }
    }

    private func restoreLastProjectOrCreateUntitled() {
        let documentController = NSDocumentController.shared
        let hasFileBackedDocuments = documentController.documents.contains { $0.fileURL != nil }
        guard !hasFileBackedDocuments else { return }

        var projectURLs = persistence.loadLastOpenedProjectURLs()
        if projectURLs.isEmpty, let lastProjectURL = persistence.loadLastOpenedProjectURL() {
            projectURLs = [lastProjectURL]
        }

        guard !projectURLs.isEmpty else { return }

        var pending = projectURLs.count
        var openedCount = 0
        for projectURL in projectURLs {
            documentController.openDocument(withContentsOf: projectURL, display: true) { document, _, error in
                if error == nil, document != nil {
                    openedCount += 1
                    documentController.noteNewRecentDocumentURL(projectURL)
                }

                pending -= 1
                if pending == 0 {
                    if openedCount > 0 {
                        self.closeTransientUntitledDocuments(using: documentController)
                    }
                }
            }
        }
    }

    private func closeTransientUntitledDocuments(using controller: NSDocumentController) {
        for document in controller.documents where document.fileURL == nil && !document.isDocumentEdited {
            document.close()
        }
    }

    private func openUntitledDocumentIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let controller = NSDocumentController.shared
            guard controller.documents.isEmpty else { return }
            controller.newDocument(nil)
        }
    }

    private func persistOpenDocumentSession() {
        let controller = NSDocumentController.shared
        let fileBackedURLs = controller.documents.compactMap { document in
            document.fileURL?.standardizedFileURL
        }

        if fileBackedURLs.isEmpty {
            persistence.clearLastOpenedProjectURL()
        } else {
            persistence.saveLastOpenedProjectURLs(fileBackedURLs)
            for projectURL in fileBackedURLs {
                controller.noteNewRecentDocumentURL(projectURL)
            }
        }
    }

    private func openDocumentDialog(using controller: NSDocumentController) {
        controller.openDocument(nil)
    }
}

@main
struct SceneApp: App {
    @NSApplicationDelegateAdaptor(SceneAppDelegate.self) private var appDelegate

    var body: some SwiftUI.Scene {
        DocumentGroup(newDocument: { SceneProjectDocument() }) { file in
            DocumentWorkspaceView(
                document: file.document,
                fileURL: file.fileURL
            )
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands {
            SceneFileCommands()
        }
    }
}
