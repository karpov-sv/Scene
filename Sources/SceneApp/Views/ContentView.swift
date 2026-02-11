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
    @State private var isCompendiumVisible: Bool = true
    @State private var isConversationsVisible: Bool = true

    private var hasErrorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }

    var body: some View {
        rootContent
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

    @ViewBuilder
    private var rootContent: some View {
        if store.isProjectOpen {
            workspaceRoot
        } else {
            closedProjectView
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
        if store.isProjectOpen {
            ToolbarItem(placement: .principal) {
                Picker("Workspace", selection: $selectedTab) {
                    ForEach(WorkspaceTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleTrailingPanelVisibility()
                } label: {
                    Image(systemName: selectedTab == .writing ? "books.vertical" : "list.bullet")
                }
                .help(toggleTrailingPanelHelpText)
            }
        }
    }

    private var workspacePanel: AnyView {
        if selectedTab == .writing {
            if !isCompendiumVisible {
                return AnyView(
                    EditorView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
            }

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

        return AnyView(
            WorkshopChatView(
                layout: .embeddedTrailingSessions,
                showsConversationsSidebar: isConversationsVisible
            )
        )
    }

    private var closedProjectView: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)

            Text("No Project Open")
                .font(.title3.weight(.semibold))

            Text("Create a new project or open an existing `.sceneproj` folder.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("New Project...") {
                    createProjectFromDialog()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Project...") {
                    openProjectFromDialog()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createProjectFromDialog() {
        let suggestedName = store.currentProjectName == "No Project" ? "Untitled" : store.currentProjectName
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

    private var toggleTrailingPanelHelpText: String {
        if selectedTab == .writing {
            return isCompendiumVisible ? "Hide Compendium" : "Show Compendium"
        }
        return isConversationsVisible ? "Hide Conversations" : "Show Conversations"
    }

    private func toggleTrailingPanelVisibility() {
        if selectedTab == .writing {
            isCompendiumVisible.toggle()
        } else {
            isConversationsVisible.toggle()
        }
    }
}
