import SwiftUI
import AppKit

@MainActor
final class SceneAppDelegate: NSObject, NSApplicationDelegate {
    private let persistence = ProjectPersistence.shared

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched from `swift run`, make the app frontmost so keyboard input
        // is delivered to the window instead of remaining in the terminal.
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.restoreLastProjectOrCreateUntitled()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        persistOpenDocumentSession()
    }

    private func restoreLastProjectOrCreateUntitled() {
        let documentController = NSDocumentController.shared
        let hasFileBackedDocuments = documentController.documents.contains { $0.fileURL != nil }
        guard !hasFileBackedDocuments else { return }

        var projectURLs = persistence.loadLastOpenedProjectURLs()
        if projectURLs.isEmpty, let lastProjectURL = persistence.loadLastOpenedProjectURL() {
            projectURLs = [lastProjectURL]
        }

        closeTransientUntitledDocuments(using: documentController)

        guard !projectURLs.isEmpty else {
            if documentController.documents.isEmpty {
                openDocumentDialog(using: documentController)
            }
            return
        }

        var pending = projectURLs.count
        var openedCount = 0
        for projectURL in projectURLs {
            documentController.openDocument(withContentsOf: projectURL, display: true) { document, _, error in
                if error == nil, document != nil {
                    openedCount += 1
                    documentController.noteNewRecentDocumentURL(projectURL)
                }

                pending -= 1
                if pending == 0 && openedCount == 0 && documentController.documents.isEmpty {
                    self.openDocumentDialog(using: documentController)
                }
            }
        }
    }

    private func closeTransientUntitledDocuments(using controller: NSDocumentController) {
        for document in controller.documents where document.fileURL == nil && !document.isDocumentEdited {
            document.close()
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
    }
}
