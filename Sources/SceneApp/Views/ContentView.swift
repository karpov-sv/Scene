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
        case conversations
    }

    @EnvironmentObject private var store: AppStore
    @AppStorage("SceneApp.ui.workspaceTab")
    private var storedWorkspaceTabRawValue: String = WorkspaceTab.writing.rawValue
    @AppStorage("SceneApp.ui.writingSidePanel")
    private var storedWritingSidePanelRawValue: String = WritingSidePanel.compendium.rawValue
    @AppStorage("SceneApp.ui.binderVisible")
    private var storedBinderVisible: Bool = true
    @AppStorage("SceneApp.ui.generationPanelVisible")
    private var storedGenerationPanelVisible: Bool = true
    @State private var summaryScope: SummaryScope = .scene
    @State private var notesScope: NotesScope = .scene
    @State private var workspaceColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingCheckpointRestoreSheet: Bool = false

    private var selectedTab: WorkspaceTab {
        get { WorkspaceTab(rawValue: store.workspaceTab) ?? .writing }
        nonmutating set { store.workspaceTab = newValue.rawValue }
    }

    private var writingSidePanel: WritingSidePanel {
        get { WritingSidePanel(rawValue: store.writingSidePanel) ?? .compendium }
        nonmutating set { store.writingSidePanel = newValue.rawValue }
    }

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
            .focusedSceneValue(\.viewMenuActions, viewMenuActions)
            .focusedSceneValue(\.checkpointMenuActions, checkpointMenuActions)
            .overlay(alignment: .bottomTrailing) {
                if store.isProjectOpen {
                    TaskNotificationToastStack(
                        toasts: store.taskNotificationToasts,
                        onDismiss: { store.dismissTaskNotificationToast($0) }
                    )
                    .padding(.trailing, 18)
                    .padding(.bottom, 16)
                }
            }
            .sheet(isPresented: $store.showingSettings) {
                SettingsSheetView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingCheckpointRestoreSheet) {
                CheckpointRestoreSheet()
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
                restoreBinderVisibilityFromStorage()
                restoreGenerationPanelVisibilityFromStorage()
            }
            .onChange(of: selectedTab) { _, newValue in
                storedWorkspaceTabRawValue = newValue.rawValue
            }
            .onChange(of: writingSidePanel) { _, newValue in
                storedWritingSidePanelRawValue = newValue.rawValue
            }
            .onChange(of: workspaceColumnVisibility) { _, newValue in
                storedBinderVisible = newValue != .detailOnly
            }
            .onChange(of: store.isGenerationPanelVisible) { _, newValue in
                storedGenerationPanelVisible = newValue
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
        NavigationSplitView(columnVisibility: $workspaceColumnVisibility) {
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
                onSelectScene: {
                    selectedTab = .writing
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
        ToolbarItem(placement: .status) {
            Picker("Workspace", selection: Binding(
                get: { selectedTab },
                set: { newTab in
                    guard selectedTab != newTab else { return }
                    selectedTab = newTab
                    switch newTab {
                    case .writing:
                        store.requestSceneEditorFocus()
                    case .workshop:
                        store.requestWorkshopInputFocus()
                    }
                }
            )) {
                ForEach(WorkspaceTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }

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

            Button {
                toggleConversationsPanel()
            } label: {
                Image(systemName: writingSidePanel == .conversations ? "text.bubble.fill" : "text.bubble")
            }
            .help(conversationsToggleHelpText)
        }
    }

    // MARK: - Workspace panels

    // Always renders inside a stable HSplitView so toggling the side panel
    // does not destroy/recreate the main panel (preserving editor state).
    private var workspacePanel: some View {
        HSplitView {
            workspaceMainPanel
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

            if writingSidePanel != .none {
                writingSidePanelContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Both tabs are kept alive via opacity/zIndex layering so switching
    // tabs doesn't destroy @State (scroll position, undo stack, etc.).
    private var workspaceMainPanel: some View {
        ZStack {
            EditorView()
                .zIndex(selectedTab == .writing ? 1 : 0)
                .opacity(selectedTab == .writing ? 1 : 0)
                .allowsHitTesting(selectedTab == .writing)

            WorkshopChatView(
                layout: .embeddedTrailingSessions,
                showsConversationsSidebar: false
            )
            .zIndex(selectedTab == .workshop ? 1 : 0)
            .opacity(selectedTab == .workshop ? 1 : 0)
            .allowsHitTesting(selectedTab == .workshop)
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
        case .conversations:
            WorkshopConversationsSidebarView { _ in
                selectedTab = .workshop
            }
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 520, maxHeight: .infinity)
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
        writingSidePanel == .conversations ? "Hide Conversations" : "Show Conversations"
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
                store.focusTextGenerationInput()
            },
            canFindInScene: store.isProjectOpen && store.selectedScene != nil,
            canFindInProject: store.isProjectOpen,
            canFindNext: !store.globalSearchResults.isEmpty || !store.lastGlobalSearchQuery.isEmpty,
            canFindPrevious: !store.globalSearchResults.isEmpty || !store.lastGlobalSearchQuery.isEmpty,
            canFocusBeatInput: store.isProjectOpen && store.selectedScene != nil
        )
    }

    private var viewMenuActions: ViewMenuActions {
        ViewMenuActions(
            toggleBinder: toggleBinderSidebar,
            switchToWriting: {
                selectedTab = .writing
                store.requestSceneEditorFocus()
            },
            switchToWorkshop: {
                selectedTab = .workshop
                store.requestWorkshopInputFocus()
            },
            toggleCompendium: toggleCompendiumPanel,
            toggleSummary: toggleSummaryPanel,
            toggleNotes: toggleNotesPanel,
            toggleConversations: toggleConversationsPanel,
            toggleTextGeneration: toggleGenerationPanel,
            canUseViewActions: store.isProjectOpen
        )
    }

    private var checkpointMenuActions: CheckpointMenuActions {
        CheckpointMenuActions(
            createCheckpoint: createCheckpointFromMenu,
            showRestoreDialog: showCheckpointRestoreDialogFromMenu,
            showSceneHistory: showSceneHistoryFromMenu,
            canCreateCheckpoint: store.canManageProjectCheckpoints,
            canRestoreCheckpoint: store.canManageProjectCheckpoints,
            canShowSceneHistory: store.isProjectOpen && store.selectedScene != nil
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
            writingSidePanel = .conversations
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

    private func toggleConversationsPanel() {
        writingSidePanel = writingSidePanel == .conversations ? .none : .conversations
    }

    private func toggleGenerationPanel() {
        guard store.isProjectOpen else { return }
        let wasInWriting = selectedTab == .writing
        selectedTab = .writing

        if store.isGenerationPanelVisible && wasInWriting {
            store.setGenerationPanelVisible(false)
        } else {
            store.focusTextGenerationInput()
        }
    }

    private func toggleBinderSidebar() {
        guard store.isProjectOpen else { return }
        workspaceColumnVisibility = workspaceColumnVisibility == .detailOnly ? .all : .detailOnly
    }

    private func restoreBinderVisibilityFromStorage() {
        workspaceColumnVisibility = storedBinderVisible ? .all : .detailOnly
    }

    private func restoreGenerationPanelVisibilityFromStorage() {
        store.setGenerationPanelVisible(storedGenerationPanelVisible)
    }

    private func restoreSidebarStateFromStorage() {
        let restoredTab = WorkspaceTab(rawValue: storedWorkspaceTabRawValue) ?? .writing
        let restoredWritingSidePanel = WritingSidePanel(rawValue: storedWritingSidePanelRawValue) ?? .compendium

        selectedTab = restoredTab
        writingSidePanel = restoredWritingSidePanel

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

    private func createCheckpointFromMenu() {
        do {
            _ = try store.createProjectCheckpointNow()
        } catch {
            store.lastError = "Checkpoint creation failed: \(error.localizedDescription)"
        }
    }

    private func showCheckpointRestoreDialogFromMenu() {
        store.refreshProjectCheckpoints()
        showingCheckpointRestoreSheet = true
    }

    private func showSceneHistoryFromMenu() {
        guard store.selectedScene != nil else { return }
        selectedTab = .writing
        store.requestSceneHistory()
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

private struct TaskNotificationToastStack: View {
    let toasts: [AppStore.TaskNotificationToast]
    let onDismiss: (UUID) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(toasts) { toast in
                TaskNotificationToastRow(toast: toast) {
                    onDismiss(toast.id)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: toasts)
        .frame(maxWidth: 360, alignment: .trailing)
    }
}

private struct TaskNotificationToastRow: View {
    let toast: AppStore.TaskNotificationToast
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(accentColor)
                .frame(width: 16, height: 16, alignment: .center)

            Text(toast.message)
                .font(.callout)
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 240, maxWidth: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accentColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private var iconName: String {
        switch toast.style {
        case .progress:
            return "hourglass"
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .cancelled:
            return "slash.circle.fill"
        }
    }

    private var accentColor: Color {
        switch toast.style {
        case .progress:
            return .blue
        case .success:
            return .green
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        case .cancelled:
            return .gray
        }
    }
}

private struct CheckpointRestoreSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCheckpointID: String?
    @State private var restoreOptions: AppStore.CheckpointRestoreOptions = .default

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Restore Checkpoint")
                        .font(.title3.weight(.semibold))
                    Text("Choose a timestamped checkpoint and select which parts to restore.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Refresh") {
                    store.refreshProjectCheckpoints()
                }
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if store.projectCheckpoints.isEmpty {
                ContentUnavailableView(
                    "No Checkpoints",
                    systemImage: "clock.badge.xmark",
                    description: Text("Create a checkpoint first, then restore from this dialog.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selectedCheckpointID) {
                        ForEach(store.projectCheckpoints) { checkpoint in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.timestampFormatter.string(from: checkpoint.createdAt))
                                    .font(.body)
                                Text(checkpoint.fileName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(checkpoint.id)
                        }
                    }
                    .frame(minWidth: 340, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            GroupBox("Restore Scope") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle("Text (scene/chapter titles and scene content)", isOn: $restoreOptions.includeText)
                                    Toggle("Summaries", isOn: $restoreOptions.includeSummaries)
                                    Toggle("Notes", isOn: $restoreOptions.includeNotes)
                                    Toggle("Compendium entries", isOn: $restoreOptions.includeCompendium)
                                    Toggle("Prompt templates", isOn: $restoreOptions.includeTemplates)
                                    Toggle("Settings (generation + editor appearance)", isOn: $restoreOptions.includeSettings)
                                    Toggle("Workshop conversations", isOn: $restoreOptions.includeWorkshop)
                                    Toggle("Input history", isOn: $restoreOptions.includeInputHistory)
                                    Toggle("Scene context + narrative state", isOn: $restoreOptions.includeSceneContext)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            GroupBox("Restore behaviour") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle("Restore deleted entries", isOn: $restoreOptions.restoreDeletedEntries)
                                    Toggle("Delete entries not in checkpoint", isOn: $restoreOptions.deleteEntriesNotInCheckpoint)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Text("Without behaviour toggles, restore updates only existing matching entries. With behaviour toggles, it can re-add deleted entries and/or remove entries that are absent from the checkpoint for selected types.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer(minLength: 0)
                Button("Restore") {
                    restoreSelectedCheckpoint()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCheckpointID == nil || restoreOptions.isNoOp)
            }
            .padding(16)
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            store.refreshProjectCheckpoints()
            if selectedCheckpointID == nil {
                selectedCheckpointID = store.projectCheckpoints.first?.id
            }
            restoreOptions = .default
        }
        .onChange(of: store.projectCheckpoints) { _, newValue in
            if newValue.isEmpty {
                selectedCheckpointID = nil
            } else if let selectedCheckpointID,
                      !newValue.contains(where: { $0.id == selectedCheckpointID }) {
                self.selectedCheckpointID = newValue.first?.id
            } else if selectedCheckpointID == nil {
                selectedCheckpointID = newValue.first?.id
            }
        }
    }

    private func restoreSelectedCheckpoint() {
        guard let selectedCheckpointID else { return }
        do {
            try store.restoreProjectCheckpoint(
                checkpointID: selectedCheckpointID,
                options: restoreOptions
            )
            dismiss()
        } catch {
            store.lastError = "Checkpoint restore failed: \(error.localizedDescription)"
        }
    }
}
