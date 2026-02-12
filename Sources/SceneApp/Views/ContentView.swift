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

    private enum WritingSidePanel {
        case none
        case compendium
        case summary
    }

    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: WorkspaceTab = .writing
    @State private var writingSidePanel: WritingSidePanel = .compendium
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

            if selectedTab == .writing {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        toggleCompendiumPanel()
                    } label: {
                        Image(systemName: writingSidePanel == .compendium ? "books.vertical.fill" : "books.vertical")
                    }
                    .foregroundStyle(writingSidePanel == .compendium ? Color.accentColor : Color.primary)
                    .help(compendiumToggleHelpText)

                    Button {
                        toggleSummaryPanel()
                    } label: {
                        Image(systemName: "text.alignleft")
                    }
                    .foregroundStyle(writingSidePanel == .summary ? Color.accentColor : Color.primary)
                    .help(summaryToggleHelpText)
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isConversationsVisible.toggle()
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .help(conversationsToggleHelpText)
                }
            }
        }
    }

    private var workspacePanel: AnyView {
        if selectedTab == .writing {
            if writingSidePanel == .none {
                return AnyView(
                    EditorView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
            }

            let sidePanel: AnyView
            switch writingSidePanel {
            case .compendium:
                sidePanel = AnyView(
                    CompendiumView()
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 520, maxHeight: .infinity)
                )
            case .summary:
                sidePanel = AnyView(
                    SceneSummaryPanelView()
                        .frame(minWidth: 320, idealWidth: 400, maxWidth: 540, maxHeight: .infinity)
                )
            case .none:
                sidePanel = AnyView(EmptyView())
            }

            return AnyView(
                HSplitView {
                    EditorView()
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

                    sidePanel
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

    private var compendiumToggleHelpText: String {
        writingSidePanel == .compendium ? "Hide Compendium" : "Show Compendium"
    }

    private var summaryToggleHelpText: String {
        writingSidePanel == .summary ? "Hide Summary" : "Show Summary"
    }

    private var conversationsToggleHelpText: String {
        isConversationsVisible ? "Hide Conversations" : "Show Conversations"
    }

    private func toggleCompendiumPanel() {
        writingSidePanel = writingSidePanel == .compendium ? .none : .compendium
    }

    private func toggleSummaryPanel() {
        writingSidePanel = writingSidePanel == .summary ? .none : .summary
    }
}
