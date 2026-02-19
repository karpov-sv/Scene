import SwiftUI
import UniformTypeIdentifiers

struct BinderSidebarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var collapsedChapterIDs: Set<UUID> = []
    @FocusState private var isSearchFieldFocused: Bool
    @State private var editingChapterID: UUID?
    @State private var editingSceneID: UUID?
    @State private var chapterToDelete: Chapter?
    @State private var sceneToDelete: (scene: Scene, chapterID: UUID)?
    @State private var isEditingProjectTitle: Bool = false
    @State private var editingTitle: String = ""
    @State private var replaceAllFeedback: String?
    @FocusState private var isRenameFieldFocused: Bool
    let onOpenProjectNotes: (() -> Void)?
    let onOpenSceneSummary: ((UUID, UUID) -> Void)?
    let onOpenSceneNotes: ((UUID, UUID) -> Void)?
    let onOpenChapterSummary: ((UUID) -> Void)?
    let onOpenChapterNotes: ((UUID) -> Void)?
    let onSelectScene: (() -> Void)?
    let onActivateSearchResult: ((AppStore.GlobalSearchResult) -> Void)?

    init(
        onOpenProjectNotes: (() -> Void)? = nil,
        onOpenSceneSummary: ((UUID, UUID) -> Void)? = nil,
        onOpenSceneNotes: ((UUID, UUID) -> Void)? = nil,
        onOpenChapterSummary: ((UUID) -> Void)? = nil,
        onOpenChapterNotes: ((UUID) -> Void)? = nil,
        onSelectScene: (() -> Void)? = nil,
        onActivateSearchResult: ((AppStore.GlobalSearchResult) -> Void)? = nil
    ) {
        self.onOpenProjectNotes = onOpenProjectNotes
        self.onOpenSceneSummary = onOpenSceneSummary
        self.onOpenSceneNotes = onOpenSceneNotes
        self.onOpenChapterSummary = onOpenChapterSummary
        self.onOpenChapterNotes = onOpenChapterNotes
        self.onSelectScene = onSelectScene
        self.onActivateSearchResult = onActivateSearchResult
    }

    private var selectedSceneBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedSceneID },
            set: { sceneID in
                guard let sceneID else { return }
                guard let chapter = store.chapters.first(where: { chapter in
                    chapter.scenes.contains(where: { $0.id == sceneID })
                }) else {
                    return
                }
                store.selectScene(sceneID, chapterID: chapter.id)
                onSelectScene?()
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.isGlobalSearchVisible {
                searchPanel
                Divider()
            }

            if isShowingSearchResults {
                searchResultsList
            } else if store.chapters.isEmpty {
                ContentUnavailableView("No Chapters", systemImage: "folder", description: Text("Create a chapter to start building your binder."))
            } else {
                List(selection: selectedSceneBinding) {
                    ForEach(store.chapters) { chapter in
                        Section(isExpanded: chapterExpandedBinding(chapter.id)) {
                            if chapter.scenes.isEmpty {
                                emptyChapterDropTarget(chapter)
                                    .listRowInsets(EdgeInsets(top: 2, leading: 28, bottom: 2, trailing: 8))
                            } else {
                                ForEach(chapter.scenes) { scene in
                                    sceneRow(scene, chapterID: chapter.id)
                                        .tag(Optional(scene.id))
                                        .listRowInsets(EdgeInsets(top: 2, leading: 28, bottom: 2, trailing: 8))
                                        .draggable("scene:\(scene.id.uuidString)")
                                }
                                .onInsert(of: [.utf8PlainText]) { index, providers in
                                    handleSceneInsert(into: chapter.id, at: index, providers: providers)
                                }
                            }
                        } header: {
                            chapterRow(chapter)
                                .contextMenu {
                                    chapterActions(chapter)
                                }
                        }
                    }
                    .onInsert(of: [.utf8PlainText]) { index, providers in
                        handleChapterInsert(at: index, providers: providers)
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()
            footerActions
        }
        .onChange(of: store.globalSearchFocusRequestID) { _, _ in
            isSearchFieldFocused = true
        }
        .onChange(of: isRenameFieldFocused) { _, focused in
            if !focused {
                if isEditingProjectTitle {
                    commitProjectRename()
                } else if let chapterID = editingChapterID {
                    commitChapterRename(chapterID)
                } else if let sceneID = editingSceneID {
                    commitSceneRename(sceneID)
                }
            }
        }
        .alert("Delete Chapter", isPresented: Binding(
            get: { chapterToDelete != nil },
            set: { if !$0 { chapterToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let chapter = chapterToDelete {
                    store.deleteChapter(chapter.id)
                    chapterToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                chapterToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete \"\(chapterToDelete?.title ?? "")\" and all its scenes?")
        }
        .alert("Delete Scene", isPresented: Binding(
            get: { sceneToDelete != nil },
            set: { if !$0 { sceneToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let info = sceneToDelete {
                    store.deleteScene(info.scene.id)
                    sceneToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                sceneToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete \"\(sceneToDelete?.scene.title ?? "")\"?")
        }
    }

    private var header: some View {
        Group {
            if isEditingProjectTitle {
                TextField("Project Title", text: $editingTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                    .focused($isRenameFieldFocused)
                    .onSubmit {
                        commitProjectRename()
                    }
                    .onExitCommand {
                        cancelRename()
                    }
            } else {
                Text(projectTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        beginProjectRename()
                    }
                    .contextMenu {
                        Button {
                            beginProjectRename()
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button {
                            onOpenProjectNotes?()
                        } label: {
                            Label("Open Project Notes", systemImage: "note.text")
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { store.globalSearchQuery },
            set: { store.updateGlobalSearchQuery($0) }
        )
    }

    private var searchScopeBinding: Binding<AppStore.GlobalSearchScope> {
        Binding(
            get: { store.globalSearchScope },
            set: { store.updateGlobalSearchScope($0) }
        )
    }

    private var selectedSearchResultBinding: Binding<String?> {
        Binding(
            get: { store.selectedGlobalSearchResultID },
            set: { store.setSelectedGlobalSearchResultID($0) }
        )
    }

    private var trimmedSearchQuery: String {
        store.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingSearchResults: Bool {
        store.isGlobalSearchVisible && !trimmedSearchQuery.isEmpty
    }

    private var replaceTextBinding: Binding<String> {
        Binding(
            get: { store.replaceText },
            set: { store.replaceText = $0 }
        )
    }

    private var isReplacementDisabled: Bool {
        store.globalSearchScope == .chats
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    store.isReplaceMode.toggle()
                } label: {
                    Image(systemName: store.isReplaceMode ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(store.isReplaceMode ? "Hide Replace" : "Show Replace")

                TextField("Search", text: searchQueryBinding)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        activateNextSearchResultFromField()
                    }
                    .onExitCommand {
                        closeSearchInterface()
                    }

                Button {
                    closeSearchInterface()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Search")
            }

            if store.isReplaceMode {
                HStack(spacing: 6) {
                    // Spacer matching the chevron button width
                    Color.clear.frame(width: 14, height: 1)

                    TextField("Replace", text: replaceTextBinding)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            _ = store.replaceCurrentSearchMatch(with: store.replaceText)
                        }

                    Button("Replace") {
                        _ = store.replaceCurrentSearchMatch(with: store.replaceText)
                    }
                    .disabled(store.selectedGlobalSearchResultID == nil || isReplacementDisabled)
                    .help("Replace current match")

                    Button("All") {
                        let count = store.replaceAllSearchMatches(with: store.replaceText)
                        if count > 0 {
                            replaceAllFeedback = "\(count) replaced"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                if replaceAllFeedback != nil {
                                    replaceAllFeedback = nil
                                }
                            }
                        }
                    }
                    .disabled(store.globalSearchResults.isEmpty || isReplacementDisabled)
                    .help("Replace all matches")
                }
            }

            ScopeFlowLayout(spacing: 4) {
                ForEach(AppStore.GlobalSearchScope.allCases) { scope in
                    scopePill(scope)
                }
            }

            if store.globalSearchScope == .scene && store.selectedSceneID == nil {
                Text("Select a scene to search within it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isShowingSearchResults {
                HStack(spacing: 6) {
                    Text("\(store.globalSearchResults.count) result\(store.globalSearchResults.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let feedback = replaceAllFeedback {
                        Text("(\(feedback))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(12)
    }

    private func scopePill(_ scope: AppStore.GlobalSearchScope) -> some View {
        let isSelected = store.globalSearchScope == scope
        return Button {
            store.updateGlobalSearchScope(scope)
        } label: {
            Text(scope.label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var searchResultsList: some View {
        ScrollViewReader { proxy in
            List(selection: selectedSearchResultBinding) {
                if store.globalSearchResults.isEmpty {
                    Text("No matches found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.globalSearchResults) { result in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: searchResultIcon(for: result.kind))
                                    .foregroundStyle(.secondary)
                                Text(result.title)
                                    .lineLimit(1)
                            }

                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            highlightedSnippet(result.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .tag(Optional(result.id))
                        .id(result.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: store.selectedGlobalSearchResultID) { _, newID in
                guard let newID,
                      let result = store.globalSearchResults.first(where: { $0.id == newID }) else { return }
                withAnimation {
                    proxy.scrollTo(newID, anchor: .center)
                }
                onActivateSearchResult?(result)
            }
        }
    }

    private func highlightedSnippet(_ snippet: String) -> Text {
        let query = store.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let range = snippet.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(snippet)
        }
        let before = String(snippet[snippet.startIndex..<range.lowerBound])
        let match = String(snippet[range])
        let after = String(snippet[range.upperBound..<snippet.endIndex])
        return Text(before) + Text(match).bold().foregroundColor(.primary) + Text(after)
    }

    private var footerActions: some View {
        HStack(spacing: 14) {
            Button {
                store.addChapter()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("New Chapter")

            Button {
                store.addScene(to: store.selectedChapterID)
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(.borderless)
            .disabled(store.selectedChapterID == nil)
            .help("New Scene")

            Spacer(minLength: 0)

            Menu {
                let modelOptions = store.generationModelOptions
                let currentModel = store.project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
                let currentModelKey = normalizedModelMenuKey(currentModel)

                if modelOptions.isEmpty {
                    Button("No known models") {}
                        .disabled(true)
                } else {
                    ForEach(modelOptions, id: \.self) { model in
                        let isCurrent = normalizedModelMenuKey(model) == currentModelKey
                        Button {
                            store.updateModel(model)
                        } label: {
                            HStack(spacing: 8) {
                                Text(model)
                                if isCurrent {
                                    Spacer(minLength: 0)
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                if !currentModel.isEmpty,
                   !modelOptions.contains(where: {
                       normalizedModelMenuKey($0) == currentModelKey
                   }) {
                    Divider()
                    Button {} label: {
                        HStack(spacing: 8) {
                            Text(currentModel)
                            Text("(current)")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(true)
                }

                if store.project.settings.provider.supportsModelDiscovery {
                    Divider()
                    Button {
                        Task {
                            await store.refreshAvailableModels(force: true, showErrors: true)
                        }
                    } label: {
                        Label("Refresh Models", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isDiscoveringModels)
                }
            } label: {
                Image(systemName: "cpu")
            }
            .buttonStyle(.borderless)
            .help("Quick Model Selection")

            Button {
                store.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Preferences")
        }
        .font(.system(size: 14, weight: .medium))
        .padding(12)
    }

    // MARK: - Chapter Row

    private func normalizedModelMenuKey(_ model: String) -> String {
        model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        HStack(spacing: 8) {
            if editingChapterID == chapter.id {
                Image(systemName: "folder")
                    .foregroundStyle(.primary)
                TextField("Chapter Title", text: $editingTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline.weight(.semibold))
                    .focused($isRenameFieldFocused)
                    .onSubmit {
                        commitChapterRename(chapter.id)
                    }
                    .onExitCommand {
                        cancelRename()
                    }
            } else {
                Label(chapterTitle(chapter), systemImage: "folder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1) {
                        store.selectChapter(chapter.id)
                    }
            }

            Spacer(minLength: 0)
        }
        .textCase(nil)
        .draggable("chapter:\(chapter.id.uuidString)")
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            return handleDropOnChapter(payload: payload, targetChapter: chapter)
        } isTargeted: { _ in }
    }

    // MARK: - Scene Row

    private func sceneRow(_ scene: Scene, chapterID: UUID) -> some View {
        Group {
            if editingSceneID == scene.id {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    TextField("Scene Title", text: $editingTitle)
                        .textFieldStyle(.roundedBorder)
                        .focused($isRenameFieldFocused)
                        .onSubmit {
                            commitSceneRename(scene.id)
                        }
                        .onExitCommand {
                            cancelRename()
                        }
                }
            } else {
                Label(sceneTitle(scene), systemImage: "doc.text")
                    .lineLimit(1)
            }
        }
        .contextMenu {
            sceneActions(scene, chapterID: chapterID)
        }
    }

    // MARK: - Rename Helpers

    private func beginProjectRename() {
        editingChapterID = nil
        editingSceneID = nil
        isEditingProjectTitle = true
        editingTitle = store.project.title
        DispatchQueue.main.async {
            isRenameFieldFocused = true
        }
    }

    private func commitProjectRename() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.updateProjectTitle(trimmed)
        }
        isEditingProjectTitle = false
    }

    private func beginChapterRename(_ chapter: Chapter) {
        editingSceneID = nil
        isEditingProjectTitle = false
        editingChapterID = chapter.id
        editingTitle = chapter.title
        DispatchQueue.main.async {
            isRenameFieldFocused = true
        }
    }

    private func beginSceneRename(_ scene: Scene) {
        editingChapterID = nil
        isEditingProjectTitle = false
        editingSceneID = scene.id
        editingTitle = scene.title
        DispatchQueue.main.async {
            isRenameFieldFocused = true
        }
    }

    private func commitChapterRename(_ chapterID: UUID) {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.renameChapter(chapterID, to: trimmed)
        }
        editingChapterID = nil
    }

    private func commitSceneRename(_ sceneID: UUID) {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.renameScene(sceneID, to: trimmed)
        }
        editingSceneID = nil
    }

    private func cancelRename() {
        editingChapterID = nil
        editingSceneID = nil
        isEditingProjectTitle = false
    }

    // MARK: - Drag & Drop Helpers

    private func emptyChapterDropTarget(_ chapter: Chapter) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Drop scene or chapter here")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            return handleDropOnChapter(payload: payload, targetChapter: chapter)
        } isTargeted: { _ in }
    }

    private func handleDropOnChapter(payload: String, targetChapter: Chapter) -> Bool {
        let parts = payload.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return false }

        let kind = String(parts[0])
        let identifier = String(parts[1])

        if kind == "scene", let sceneID = UUID(uuidString: identifier) {
            store.moveScene(sceneID, toChapterID: targetChapter.id, atIndex: targetChapter.scenes.count)
            return true
        }

        if kind == "chapter", let chapterID = UUID(uuidString: identifier) {
            guard let targetChapterIndex = chapterIndex(for: targetChapter.id) else { return false }
            moveChapter(chapterID, toInsertionIndex: targetChapterIndex + 1)
            return true
        }

        return false
    }

    private func handleChapterInsert(at index: Int, providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, _ in
            guard let data = data as? Data,
                  let payload = String(data: data, encoding: .utf8) else { return }
            let parts = payload.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  String(parts[0]) == "chapter",
                  let chapterID = UUID(uuidString: String(parts[1])) else { return }
            DispatchQueue.main.async {
                moveChapter(chapterID, toInsertionIndex: index)
            }
        }
    }

    private func handleSceneInsert(into chapterID: UUID, at index: Int, providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, _ in
            guard let data = data as? Data,
                  let payload = String(data: data, encoding: .utf8) else { return }
            let parts = payload.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return }

            if String(parts[0]) == "chapter" {
                guard let chapterIDToMove = UUID(uuidString: String(parts[1])) else { return }
                DispatchQueue.main.async {
                    guard let targetChapterIndex = chapterIndex(for: chapterID) else { return }
                    moveChapter(chapterIDToMove, toInsertionIndex: targetChapterIndex + 1)
                }
                return
            }

            guard String(parts[0]) == "scene",
                  let sceneID = UUID(uuidString: String(parts[1])) else { return }

            DispatchQueue.main.async {
                var targetIndex = index
                if let sourceLocation = sceneLocation(for: sceneID),
                   sourceLocation.chapterID == chapterID,
                   sourceLocation.sceneIndex < index {
                    targetIndex -= 1
                }
                store.moveScene(sceneID, toChapterID: chapterID, atIndex: targetIndex)
            }
        }
    }

    private func moveChapter(_ chapterID: UUID, toInsertionIndex index: Int) {
        var targetIndex = index
        if let sourceChapterIndex = chapterIndex(for: chapterID),
           sourceChapterIndex < index {
            targetIndex -= 1
        }
        store.moveChapter(chapterID, toIndex: targetIndex)
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func chapterActions(_ chapter: Chapter) -> some View {
        Button {
            beginChapterRename(chapter)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            store.addScene(to: chapter.id)
        } label: {
            Label("Add Scene", systemImage: "plus")
        }

        Button {
            onOpenChapterSummary?(chapter.id)
        } label: {
            Label("Open Chapter Summary", systemImage: "text.alignleft")
        }

        Button {
            onOpenChapterNotes?(chapter.id)
        } label: {
            Label("Open Chapter Notes", systemImage: "note.text")
        }

        Button {
            store.moveChapterUp(chapter.id)
        } label: {
            Label("Move Chapter Up", systemImage: "arrow.up")
        }
        .disabled(!store.canMoveChapterUp(chapter.id))

        Button {
            store.moveChapterDown(chapter.id)
        } label: {
            Label("Move Chapter Down", systemImage: "arrow.down")
        }
        .disabled(!store.canMoveChapterDown(chapter.id))

        Button(role: .destructive) {
            chapterToDelete = chapter
        } label: {
            Label("Delete Chapter", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func sceneActions(_ scene: Scene, chapterID: UUID) -> some View {
        Button {
            beginSceneRename(scene)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            onOpenSceneSummary?(scene.id, chapterID)
        } label: {
            Label("Open Scene Summary", systemImage: "text.alignleft")
        }

        Button {
            onOpenSceneNotes?(scene.id, chapterID)
        } label: {
            Label("Open Scene Notes", systemImage: "note.text")
        }

        Button {
            store.moveSceneUp(scene.id)
        } label: {
            Label("Move Scene Up", systemImage: "arrow.up")
        }
        .disabled(!store.canMoveSceneUp(scene.id))

        Button {
            store.moveSceneDown(scene.id)
        } label: {
            Label("Move Scene Down", systemImage: "arrow.down")
        }
        .disabled(!store.canMoveSceneDown(scene.id))

        Button(role: .destructive) {
            sceneToDelete = (scene, chapterID)
        } label: {
            Label("Delete Scene", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private func chapterTitle(_ chapter: Chapter) -> String {
        let trimmed = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chapter" : trimmed
    }

    private func chapterIndex(for chapterID: UUID) -> Int? {
        store.chapters.firstIndex(where: { $0.id == chapterID })
    }

    private func sceneLocation(for sceneID: UUID) -> (chapterID: UUID, sceneIndex: Int)? {
        for chapter in store.chapters {
            if let sceneIndex = chapter.scenes.firstIndex(where: { $0.id == sceneID }) {
                return (chapter.id, sceneIndex)
            }
        }
        return nil
    }

    private func sceneTitle(_ scene: Scene) -> String {
        let trimmed = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Scene" : trimmed
    }

    private func searchResultIcon(for kind: AppStore.GlobalSearchResult.Kind) -> String {
        switch kind {
        case .scene:
            return "doc.text.magnifyingglass"
        case .compendium:
            return "books.vertical"
        case .sceneSummary, .chapterSummary:
            return "text.alignleft"
        case .projectNote, .chapterNote, .sceneNote:
            return "note.text"
        case .chatMessage:
            return "bubble.left.and.bubble.right"
        }
    }

    private var projectTitle: String {
        let trimmed = store.project.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Project" : trimmed
    }

    private func chapterExpandedBinding(_ chapterID: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsedChapterIDs.contains(chapterID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedChapterIDs.remove(chapterID)
                } else {
                    collapsedChapterIDs.insert(chapterID)
                }
            }
        )
    }

    private func activateNextSearchResultFromField() {
        if let result = store.selectNextGlobalSearchResult() {
            onActivateSearchResult?(result)
        }
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }

    private func closeSearchInterface() {
        store.dismissGlobalSearch()
        isSearchFieldFocused = false
    }
}

private struct ScopeFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeRows(proposal: proposal, subviews: subviews)
        guard let lastRow = rows.last else { return .zero }
        let height = lastRow.origin.y + lastRow.height
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeRows(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.origin.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private struct RowItem {
        let index: Int
        let x: CGFloat
        let size: CGSize
    }

    private struct Row {
        var origin: CGPoint
        var height: CGFloat
        var items: [RowItem]
    }

    private func arrangeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentRow = Row(origin: .zero, height: 0, items: [])
        var x: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !currentRow.items.isEmpty && x + size.width > maxWidth {
                rows.append(currentRow)
                let nextY = currentRow.origin.y + currentRow.height + spacing
                currentRow = Row(origin: CGPoint(x: 0, y: nextY), height: 0, items: [])
                x = 0
            }
            currentRow.items.append(RowItem(index: index, x: x, size: size))
            currentRow.height = max(currentRow.height, size.height)
            x += size.width + spacing
        }

        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }
}
