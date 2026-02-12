import SwiftUI

struct DocumentWorkspaceView: View {
    @ObservedObject var document: SceneProjectDocument
    let fileURL: URL?

    @StateObject private var store: AppStore

    init(document: SceneProjectDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _store = StateObject(
            wrappedValue: AppStore(
                documentProject: document.project,
                projectURL: fileURL
            )
        )
    }

    var body: some View {
        ContentView()
            .environmentObject(store)
            .frame(minWidth: 1200, minHeight: 760)
            .onAppear {
                store.bindToDocumentChanges { updatedProject in
                    document.project = updatedProject
                }
                store.updateProjectURL(fileURL)
                store.synchronizeProjectToDocument()
            }
            .onChange(of: fileURL) { _, newValue in
                store.updateProjectURL(newValue)
            }
    }
}
