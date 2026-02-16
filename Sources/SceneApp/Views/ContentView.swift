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

    private enum WritingSidePanel: String {
        case none
        case compendium
        case summary
        case notes
    }

    @EnvironmentObject private var store: AppStore
    @AppStorage("SceneApp.ui.workspaceTab")
    private var storedWorkspaceTabRawValue: String = WorkspaceTab.writing.rawValue
    @AppStorage("SceneApp.ui.writingSidePanel")
    private var storedWritingSidePanelRawValue: String = WritingSidePanel.compendium.rawValue
    @AppStorage("SceneApp.ui.workshopConversationsVisible")
    private var storedWorkshopConversationsVisible: Bool = true
    @State private var selectedTab: WorkspaceTab = .writing
    @State private var writingSidePanel: WritingSidePanel = .compendium
    @State private var summaryScope: SummaryScope = .scene
    @State private var notesScope: NotesScope = .scene
    @State private var isConversationsVisible: Bool = true

    private var hasErrorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }

    var body: some View {
        rootContent
            .focusedSceneValue(\.projectMenuActions, projectMenuActions)
            .focusedSceneValue(\.searchMenuActions, searchMenuActions)
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
            .onAppear {
                restoreSidebarStateFromStorage()
            }
            .onChange(of: selectedTab) { _, newValue in
                storedWorkspaceTabRawValue = newValue.rawValue
            }
            .onChange(of: writingSidePanel) { _, newValue in
                storedWritingSidePanelRawValue = newValue.rawValue
            }
            .onChange(of: isConversationsVisible) { _, newValue in
                storedWorkshopConversationsVisible = newValue
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
            BinderSidebarView(
                onOpenProjectNotes: {
                    selectedTab = .writing
                    writingSidePanel = .notes
                    notesScope = .project
                },
                onOpenSceneSummary: { sceneID, chapterID in
                    store.selectScene(sceneID, chapterID: chapterID)
                    summaryScope = .scene
                    selectedTab = .writing
                    writingSidePanel = .summary
                },
                onOpenSceneNotes: { sceneID, chapterID in
                    store.selectScene(sceneID, chapterID: chapterID)
                    notesScope = .scene
                    selectedTab = .writing
                    writingSidePanel = .notes
                },
                onOpenChapterSummary: { chapterID in
                    store.selectChapter(chapterID)
                    summaryScope = .chapter
                    selectedTab = .writing
                    writingSidePanel = .summary
                },
                onOpenChapterNotes: { chapterID in
                    store.selectChapter(chapterID)
                    notesScope = .chapter
                    selectedTab = .writing
                    writingSidePanel = .notes
                },
                onActivateSearchResult: activateSearchResult
            )
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
            ToolbarItem(placement: .status) {
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
                    .help(compendiumToggleHelpText)

                    Button {
                        toggleSummaryPanel()
                    } label: {
                        Image(systemName: writingSidePanel == .summary ? "text.document.fill" : "text.document")
                    }
                    .help(summaryToggleHelpText)

                    Button {
                        toggleNotesPanel()
                    } label: {
                        Image(systemName: writingSidePanel == .notes ? "list.clipboard.fill" : "list.clipboard")
                    }
                    .help(notesToggleHelpText)
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

    @ViewBuilder
    private var workspacePanel: some View {
        if selectedTab == .writing {
            if writingSidePanel == .none {
                EditorView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    EditorView()
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

                    writingSidePanelContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            WorkshopChatView(
                layout: .embeddedTrailingSessions,
                showsConversationsSidebar: isConversationsVisible
            )
        }
    }

    @ViewBuilder
    private var writingSidePanelContent: some View {
        switch writingSidePanel {
        case .compendium:
            CompendiumView()
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 520, maxHeight: .infinity)
        case .summary:
            SceneSummaryPanelView(scope: $summaryScope)
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 540, maxHeight: .infinity)
        case .notes:
            NotesPanelView(scope: $notesScope)
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 540, maxHeight: .infinity)
        case .none:
            EmptyView()
        }
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

    private var notesToggleHelpText: String {
        writingSidePanel == .notes ? "Hide Notes" : "Show Notes"
    }

    private var conversationsToggleHelpText: String {
        isConversationsVisible ? "Hide Conversations" : "Show Conversations"
    }

    private var projectMenuActions: ProjectMenuActions {
        ProjectMenuActions(
            importProjectJSON: importProjectJSONFromMenu,
            importProjectEPUB: importProjectEPUBFromMenu,
            exportProjectJSON: exportProjectJSONFromMenu,
            exportProjectPlainText: exportProjectPlainTextFromMenu,
            exportProjectHTML: exportProjectHTMLFromMenu,
            exportProjectEPUB: exportProjectEPUBFromMenu,
            openProjectSettings: { store.showingSettings = true },
            canExportProject: store.isProjectOpen,
            canOpenProjectSettings: store.isProjectOpen
        )
    }

    private var searchMenuActions: SearchMenuActions {
        SearchMenuActions(
            findInScene: {
                store.requestGlobalSearchFocus(scope: .scene)
            },
            findInProject: {
                store.requestGlobalSearchFocus(scope: .all)
            },
            findNext: activateNextSearchResult,
            findPrevious: activatePreviousSearchResult,
            focusBeatInput: {
                selectedTab = .writing
                store.requestBeatInputFocus()
            },
            canFindInScene: store.isProjectOpen && store.selectedScene != nil,
            canFindInProject: store.isProjectOpen,
            canFindNext: !store.globalSearchResults.isEmpty || !store.lastGlobalSearchQuery.isEmpty,
            canFindPrevious: !store.globalSearchResults.isEmpty || !store.lastGlobalSearchQuery.isEmpty,
            canFocusBeatInput: store.isProjectOpen && store.selectedScene != nil
        )
    }

    private func activateNextSearchResult() {
        if store.globalSearchResults.isEmpty {
            store.restoreLastSearchIfNeeded()
        }
        guard let result = store.selectNextGlobalSearchResult() else { return }
        activateSearchResult(result)
    }

    private func activatePreviousSearchResult() {
        if store.globalSearchResults.isEmpty {
            store.restoreLastSearchIfNeeded()
        }
        guard let result = store.selectPreviousGlobalSearchResult() else { return }
        activateSearchResult(result)
    }

    private func activateSearchResult(_ result: AppStore.GlobalSearchResult) {
        switch result.kind {
        case .scene:
            guard let chapterID = result.chapterID,
                  let sceneID = result.sceneID else {
                return
            }
            selectedTab = .writing
            store.revealSceneSearchMatch(
                chapterID: chapterID,
                sceneID: sceneID,
                location: result.location ?? 0,
                length: result.length ?? 0
            )

        case .compendium:
            guard let entryID = result.compendiumEntryID else { return }
            selectedTab = .writing
            writingSidePanel = .compendium
            store.selectCompendiumEntry(entryID)

        case .sceneSummary:
            guard let chapterID = result.chapterID,
                  let sceneID = result.sceneID else {
                return
            }
            selectedTab = .writing
            writingSidePanel = .summary
            summaryScope = .scene
            store.selectScene(sceneID, chapterID: chapterID)

        case .chapterSummary:
            guard let chapterID = result.chapterID else { return }
            selectedTab = .writing
            writingSidePanel = .summary
            summaryScope = .chapter
            store.selectChapter(chapterID)

        case .projectNote:
            selectedTab = .writing
            writingSidePanel = .notes
            notesScope = .project

        case .chapterNote:
            guard let chapterID = result.chapterID else { return }
            selectedTab = .writing
            writingSidePanel = .notes
            notesScope = .chapter
            store.selectChapter(chapterID)

        case .sceneNote:
            guard let chapterID = result.chapterID,
                  let sceneID = result.sceneID else {
                return
            }
            selectedTab = .writing
            writingSidePanel = .notes
            notesScope = .scene
            store.selectScene(sceneID, chapterID: chapterID)

        case .chatMessage:
            guard let sessionID = result.workshopSessionID else { return }
            selectedTab = .workshop
            isConversationsVisible = true
            store.selectWorkshopSession(sessionID)
        }
    }

    private func toggleCompendiumPanel() {
        writingSidePanel = writingSidePanel == .compendium ? .none : .compendium
    }

    private func toggleSummaryPanel() {
        writingSidePanel = writingSidePanel == .summary ? .none : .summary
    }

    private func toggleNotesPanel() {
        writingSidePanel = writingSidePanel == .notes ? .none : .notes
    }

    private func restoreSidebarStateFromStorage() {
        let restoredTab = WorkspaceTab(rawValue: storedWorkspaceTabRawValue) ?? .writing
        let restoredWritingSidePanel = WritingSidePanel(rawValue: storedWritingSidePanelRawValue) ?? .compendium

        selectedTab = restoredTab
        writingSidePanel = restoredWritingSidePanel
        isConversationsVisible = storedWorkshopConversationsVisible

        if storedWorkspaceTabRawValue != restoredTab.rawValue {
            storedWorkspaceTabRawValue = restoredTab.rawValue
        }
        if storedWritingSidePanelRawValue != restoredWritingSidePanel.rawValue {
            storedWritingSidePanelRawValue = restoredWritingSidePanel.rawValue
        }
    }

    private func importProjectJSONFromMenu() {
        guard let fileURL = ProjectDialogs.chooseProjectExchangeImportURL() else {
            return
        }
        let suggestedName = fileURL.deletingPathExtension().lastPathComponent
        guard let destinationURL = ProjectDialogs.chooseImportedProjectURL(suggestedName: suggestedName) else {
            return
        }

        do {
            let projectURL = try store.createProjectFromImportedExchange(from: fileURL, at: destinationURL)
            openImportedProjectInNewWindow(projectURL)
        } catch {
            store.lastError = "Project import failed: \(error.localizedDescription)"
        }
    }

    private func exportProjectJSONFromMenu() {
        guard let fileURL = ProjectDialogs.chooseProjectExchangeExportURL(defaultProjectName: store.currentProjectName) else {
            return
        }

        do {
            try store.exportProjectExchange(to: fileURL)
        } catch {
            store.lastError = "Project export failed: \(error.localizedDescription)"
        }
    }

    private func exportProjectPlainTextFromMenu() {
        guard let fileURL = ProjectDialogs.chooseProjectTextExportURL(defaultProjectName: store.currentProjectName) else {
            return
        }

        do {
            try store.exportProjectAsPlainText(to: fileURL)
        } catch {
            store.lastError = "Plain text export failed: \(error.localizedDescription)"
        }
    }

    private func exportProjectHTMLFromMenu() {
        guard let fileURL = ProjectDialogs.chooseProjectHTMLExportURL(defaultProjectName: store.currentProjectName) else {
            return
        }

        do {
            try store.exportProjectAsHTML(to: fileURL)
        } catch {
            store.lastError = "HTML export failed: \(error.localizedDescription)"
        }
    }

    private func exportProjectEPUBFromMenu() {
        guard let fileURL = ProjectDialogs.chooseProjectEPUBExportURL(defaultProjectName: store.currentProjectName) else {
            return
        }

        do {
            try store.exportProjectAsEPUB(to: fileURL)
        } catch {
            store.lastError = "EPUB export failed: \(error.localizedDescription)"
        }
    }

    private func importProjectEPUBFromMenu() {
        guard let fileURL = ProjectDialogs.chooseProjectEPUBImportURL() else {
            return
        }
        let suggestedName = fileURL.deletingPathExtension().lastPathComponent
        guard let destinationURL = ProjectDialogs.chooseImportedProjectURL(suggestedName: suggestedName) else {
            return
        }

        do {
            let projectURL = try store.createProjectFromImportedEPUB(from: fileURL, at: destinationURL)
            openImportedProjectInNewWindow(projectURL)
        } catch {
            store.lastError = "EPUB import failed: \(error.localizedDescription)"
        }
    }

    private func openImportedProjectInNewWindow(_ projectURL: URL) {
        let normalizedURL = projectURL.standardizedFileURL
        NSDocumentController.shared.openDocument(withContentsOf: normalizedURL, display: true) { _, _, error in
            if let error {
                store.lastError = "Imported project was created, but opening a new window failed: \(error.localizedDescription)"
            }
        }
    }
}
