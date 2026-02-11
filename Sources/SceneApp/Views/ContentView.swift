import SwiftUI

struct ContentView: View {
    private enum WorkspaceTab: Hashable {
        case writing
        case workshop
    }

    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: WorkspaceTab = .writing

    private var hasErrorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            writingWorkspace
                .tabItem {
                    Label("Writing", systemImage: "square.and.pencil")
                }
                .tag(WorkspaceTab.writing)

            WorkshopChatView()
                .tabItem {
                    Label("Workshop", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(WorkspaceTab.workshop)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if selectedTab == .writing {
                    Button {
                        store.addChapter()
                    } label: {
                        Label("New Chapter", systemImage: "folder.badge.plus")
                    }

                    Button {
                        store.addScene(to: store.selectedChapterID)
                    } label: {
                        Label("New Scene", systemImage: "doc.badge.plus")
                    }
                } else {
                    Button {
                        store.createWorkshopSession()
                    } label: {
                        Label("New Chat", systemImage: "plus.bubble")
                    }
                }

                Button {
                    store.showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $store.showingSettings) {
            SettingsSheetView()
                .environmentObject(store)
        }
        .alert("Error", isPresented: hasErrorBinding) {
            Button("OK", role: .cancel) {
                store.lastError = nil
            }
        } message: {
            Text(store.lastError ?? "Unknown error")
        }
    }

    private var writingWorkspace: some View {
        NavigationSplitView {
            BinderSidebarView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 360)
        } content: {
            EditorView()
                .navigationSplitViewColumnWidth(min: 540, ideal: 700, max: 900)
        } detail: {
            CompendiumView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
