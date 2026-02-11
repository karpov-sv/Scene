import SwiftUI

struct ContentView: View {
    private enum WorkspaceTab: String, CaseIterable, Hashable, Identifiable {
        case writing
        case workshop

        var id: String { rawValue }

        var title: String {
            switch self {
            case .writing:
                return "Writing"
            case .workshop:
                return "Workshop"
            }
        }
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
        workspaceRoot
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

    private var workspaceRoot: some View {
        NavigationSplitView {
            BinderSidebarView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 360)
        } detail: {
            workspacePanel
                .navigationSplitViewColumnWidth(min: 860, ideal: 1080, max: 2400)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { workspaceToolbar }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Workspace", selection: $selectedTab) {
                ForEach(WorkspaceTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }

        ToolbarItemGroup(placement: .primaryAction) {
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

    private var workspacePanel: AnyView {
        if selectedTab == .writing {
            return AnyView(
                HSplitView {
                    EditorView()
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

                    CompendiumView()
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 520, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        return AnyView(WorkshopChatView(layout: .embeddedTrailingSessions))
    }
}
