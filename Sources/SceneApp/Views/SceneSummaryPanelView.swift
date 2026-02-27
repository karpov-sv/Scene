import SwiftUI

struct SceneSummaryPanelView: View {
    @EnvironmentObject private var store: AppStore
    @Binding private var scope: SummaryScope
    @State private var summaryTask: Task<Void, Never>?
    @State private var sceneRollingMemoryTask: Task<Void, Never>?
    @State private var isSceneRollingMemorySheetPresented: Bool = false
    @State private var sceneRollingMemoryDraft: String = ""
    @State private var sceneRollingMemoryRefreshError: String = ""
    @State private var chapterRollingMemoryTask: Task<Void, Never>?
    @State private var isChapterRollingMemorySheetPresented: Bool = false
    @State private var chapterRollingMemoryDraft: String = ""
    @State private var chapterRollingMemoryRefreshError: String = ""
    @State private var storyMemoryTask: Task<Void, Never>?
    @State private var isStoryMemorySheetPresented: Bool = false
    @State private var storyMemoryError: String = ""
    @State private var summaryRevealRequest: RevealableTextEditor.RevealRequest?

    init(scope: Binding<SummaryScope>) {
        self._scope = scope
    }

    private var selectedSummaryPromptBinding: Binding<UUID?> {
        Binding(
            get: { store.project.selectedSummaryPromptID },
            set: { store.setSelectedSummaryPrompt($0) }
        )
    }

    private var summaryBinding: Binding<String> {
        Binding(
            get: {
                switch scope {
                case .scene:
                    return store.selectedScene?.summary ?? ""
                case .chapter:
                    return store.selectedChapter?.summary ?? ""
                }
            },
            set: { value in
                switch scope {
                case .scene:
                    store.updateSelectedSceneSummary(value)
                case .chapter:
                    store.updateSelectedChapterSummary(value)
                }
            }
        )
    }

    private var summaryCharacterCount: Int {
        switch scope {
        case .scene:
            return store.selectedScene?.summary.count ?? 0
        case .chapter:
            return store.selectedChapter?.summary.count ?? 0
        }
    }

    private var summaryTitle: String {
        switch scope {
        case .scene:
            return "Scene Summary"
        case .chapter:
            return "Chapter Summary"
        }
    }

    private var summaryDescription: String {
        switch scope {
        case .scene:
            return "Generate and edit a persistent summary for the selected scene."
        case .chapter:
            return "Generate and edit a persistent summary for the selected chapter."
        }
    }

    private var canSummarizeCurrentScope: Bool {
        switch scope {
        case .scene:
            return store.selectedScene != nil
        case .chapter:
            return store.selectedChapter != nil
        }
    }

    private var canClearCurrentScope: Bool {
        guard canSummarizeCurrentScope, !isSummarizing else {
            return false
        }
        return !summaryBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSummarizing: Bool {
        summaryTask != nil
    }

    private var isRefreshingSceneRollingMemory: Bool {
        sceneRollingMemoryTask != nil
    }

    private var isRefreshingChapterRollingMemory: Bool {
        chapterRollingMemoryTask != nil
    }

    private var isRefreshingStoryMemory: Bool {
        storyMemoryTask != nil
    }

    private var sceneMemorySheetTitle: String {
        guard let scene = store.selectedScene else { return "Untitled Scene" }
        let trimmed = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Scene" : trimmed
    }

    private var chapterMemorySheetTitle: String {
        guard let chapter = store.selectedChapter else { return "Untitled Chapter" }
        let trimmed = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chapter" : trimmed
    }

    private var sceneSummarySourceText: String {
        guard scope == .scene else { return "" }
        return summaryBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sceneFullSourceText: String {
        store.selectedScene?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var chapterSummarySourceText: String {
        summaryBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chapterFullSourceText: String {
        store.selectedChapterRollingMemorySourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chapterCurrentSceneSourceText: String {
        store.selectedChapterRollingMemorySourceTextCurrentScene
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chapterUpToSelectedSceneSourceText: String {
        store.selectedChapterRollingMemorySourceTextUpToSelectedScene
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("", selection: $scope) {
                ForEach(SummaryScope.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(6)
            .padding(.top, 6)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Picker("Summary Template", selection: selectedSummaryPromptBinding) {
                        ForEach(store.summaryPrompts) { prompt in
                            Text(prompt.title)
                                .tag(Optional(prompt.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    .disabled(store.summaryPrompts.isEmpty || isSummarizing)

                    Spacer(minLength: 0)

                    Button("Clear") {
                        clearCurrentScope()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canClearCurrentScope)

                    Button {
                        if isSummarizing {
                            cancelSummarization()
                        } else {
                            summarizeCurrentScope()
                        }
                    } label: {
                        Group {
                            if isSummarizing {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Stop")
                                }
                            } else {
                                Label("Summarize", systemImage: "text.insert")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isSummarizing ? .red : .accentColor)
                    .disabled(
                        !isSummarizing
                            && (
                                !canSummarizeCurrentScope
                                || store.activeSummaryPrompt == nil
                            )
                    )
                }
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("\(summaryTitle) (\(summaryCharacterCount) chars)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                RevealableTextEditor(
                    text: summaryBinding,
                    revealRequest: summaryRevealRequest
                )
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        Rectangle()
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .overlay {
                        if isSummarizing {
                            ZStack {
                                Color(nsColor: .textBackgroundColor).opacity(0.7)
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Generating summary...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .disabled(isSummarizing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(
            isPresented: $isSceneRollingMemorySheetPresented,
            content: sceneRollingMemorySheetContent
        )
        .sheet(
            isPresented: $isChapterRollingMemorySheetPresented,
            content: chapterRollingMemorySheetContent
        )
        .sheet(
            isPresented: $isStoryMemorySheetPresented,
            content: storyMemorySheetContent
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: scope) { _, nextScope in
            if nextScope != .scene {
                cancelSceneRollingMemoryRefresh()
                sceneRollingMemoryRefreshError = ""
                isSceneRollingMemorySheetPresented = false
            }
            if nextScope != .chapter {
                cancelChapterRollingMemoryRefresh()
                chapterRollingMemoryRefreshError = ""
                isChapterRollingMemorySheetPresented = false
            }
        }
        .onChange(of: store.selectedSceneID) { _, _ in
            cancelSceneRollingMemoryRefresh()
            sceneRollingMemoryRefreshError = ""
            isSceneRollingMemorySheetPresented = false
        }
        .onChange(of: store.selectedChapterID) { _, _ in
            cancelChapterRollingMemoryRefresh()
            chapterRollingMemoryRefreshError = ""
            isChapterRollingMemorySheetPresented = false
        }
        .onDisappear {
            cancelSummarization()
            cancelSceneRollingMemoryRefresh()
            cancelChapterRollingMemoryRefresh()
            cancelStoryMemoryRefresh()
        }
        .onChange(of: store.pendingSummaryTextReveal?.requestID) { _, _ in
            guard let reveal = store.pendingSummaryTextReveal else { return }
            summaryRevealRequest = .init(
                id: reveal.requestID,
                location: reveal.location,
                length: reveal.length
            )
            store.consumeSummaryTextReveal()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text("Summary")
                    .font(.headline)

                Spacer(minLength: 0)

                Button {
                    storyMemoryError = ""
                    isStoryMemorySheetPresented = true
                } label: {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(.borderless)
                .help("Inspect inferred story memory and knowledge graph.")
                .disabled(!store.isProjectOpen)

                if scope == .scene {
                    Button {
                        sceneRollingMemoryDraft = store.selectedSceneRollingMemorySummary
                        sceneRollingMemoryRefreshError = ""
                        isSceneRollingMemorySheetPresented = true
                    } label: {
                        Image(systemName: "text.book.closed")
                    }
                    .buttonStyle(.borderless)
                    .help("Show and edit rolling memory for this scene.")
                    .disabled(store.selectedScene == nil)
                }

                if scope == .chapter {
                    Button {
                        chapterRollingMemoryDraft = store.selectedChapterRollingMemorySummary
                        chapterRollingMemoryRefreshError = ""
                        isChapterRollingMemorySheetPresented = true
                    } label: {
                        Image(systemName: "text.book.closed")
                    }
                    .buttonStyle(.borderless)
                    .help("Show and edit rolling memory for this chapter.")
                    .disabled(store.selectedChapter == nil)
                }
            }
            Text(summaryDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func summarizeCurrentScope() {
        guard !isSummarizing else { return }
        guard canSummarizeCurrentScope else { return }

        let targetScope = scope
        summaryTask = Task { @MainActor in
            defer {
                summaryTask = nil
            }

            do {
                switch targetScope {
                case .scene:
                    _ = try await store.summarizeSelectedScene()
                case .chapter:
                    _ = try await store.summarizeSelectedChapter()
                }
            } catch is CancellationError {
                return
            } catch {
                store.lastError = error.localizedDescription
            }
        }
    }

    private func cancelSummarization() {
        summaryTask?.cancel()
    }

    @ViewBuilder
    private func sceneRollingMemorySheetContent() -> some View {
        SceneRollingMemorySheet(
            sceneTitle: sceneMemorySheetTitle,
            updatedAt: store.selectedSceneRollingMemoryUpdatedAt,
            draftSummary: $sceneRollingMemoryDraft,
            canUpdateFromSummaryText: !sceneSummarySourceText.isEmpty,
            canUpdateFromFullSceneText: !sceneFullSourceText.isEmpty,
            isUpdating: isRefreshingSceneRollingMemory,
            updateErrorMessage: sceneRollingMemoryRefreshError.isEmpty ? nil : sceneRollingMemoryRefreshError,
            onSave: {
                store.updateSelectedSceneRollingMemory(sceneRollingMemoryDraft)
            },
            onClear: {
                sceneRollingMemoryDraft = ""
                store.updateSelectedSceneRollingMemory("")
            },
            onUpdateFromSummaryText: {
                refreshSceneRollingMemory(from: sceneSummarySourceText)
            },
            onUpdateFromFullSceneText: {
                refreshSceneRollingMemory(from: sceneFullSourceText)
            }
        )
    }

    @ViewBuilder
    private func chapterRollingMemorySheetContent() -> some View {
        ChapterRollingMemorySheet(
            chapterTitle: chapterMemorySheetTitle,
            updatedAt: store.selectedChapterRollingMemoryUpdatedAt,
            draftSummary: $chapterRollingMemoryDraft,
            canUpdateFromChapterSummary: !chapterSummarySourceText.isEmpty,
            canUpdateFromCurrentSceneText: !chapterCurrentSceneSourceText.isEmpty,
            canUpdateFromFullChapterText: !chapterFullSourceText.isEmpty,
            canUpdateFromUpToSelectedSceneText: !chapterUpToSelectedSceneSourceText.isEmpty,
            isUpdating: isRefreshingChapterRollingMemory,
            updateErrorMessage: chapterRollingMemoryRefreshError.isEmpty ? nil : chapterRollingMemoryRefreshError,
            onSave: {
                store.updateSelectedChapterRollingMemory(chapterRollingMemoryDraft)
            },
            onClear: {
                chapterRollingMemoryDraft = ""
                store.updateSelectedChapterRollingMemory("")
            },
            onUpdateFromChapterSummary: {
                refreshChapterRollingMemory(from: chapterSummarySourceText)
            },
            onUpdateFromCurrentSceneText: {
                refreshChapterRollingMemory(fromSceneSource: .currentScene)
            },
            onUpdateFromFullChapterText: {
                refreshChapterRollingMemory(fromSceneSource: .fullChapter)
            },
            onUpdateFromUpToSelectedSceneText: {
                refreshChapterRollingMemory(fromSceneSource: .upToSelectedScene)
            }
        )
    }

    @ViewBuilder
    private func storyMemorySheetContent() -> some View {
        AutoStoryMemorySheet(
            sceneSummary: store.selectedSceneStoryMemorySummary,
            sceneFacts: store.selectedSceneStoryMemoryFacts,
            sceneOpenThreads: store.selectedSceneStoryMemoryOpenThreads,
            sceneUpdatedAt: store.selectedSceneStoryMemoryUpdatedAt,
            chapterSummary: store.selectedChapterStoryMemorySummary,
            chapterOpenThreads: store.selectedChapterStoryMemoryOpenThreads,
            chapterUpdatedAt: store.selectedChapterStoryMemoryUpdatedAt,
            projectSummary: store.projectStoryMemorySummary,
            projectOpenThreads: store.projectStoryMemoryOpenThreads,
            projectUpdatedAt: store.projectStoryMemoryUpdatedAt,
            relevantKnowledge: store.selectedSceneRelevantStoryKnowledge,
            isUpdating: isRefreshingStoryMemory,
            updateErrorMessage: storyMemoryError.isEmpty ? nil : storyMemoryError,
            onRebuildScene: rebuildSelectedStoryMemory,
            onRebuildProject: rebuildProjectStoryMemory
        )
    }

    private func refreshSceneRollingMemory(from sourceText: String) {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return }

        cancelSceneRollingMemoryRefresh()
        sceneRollingMemoryRefreshError = ""

        sceneRollingMemoryTask = Task { @MainActor in
            defer {
                sceneRollingMemoryTask = nil
            }

            do {
                let refreshed = try await store.refreshSelectedSceneRollingMemory(from: trimmedSource)
                sceneRollingMemoryDraft = refreshed
            } catch is CancellationError {
                return
            } catch {
                sceneRollingMemoryRefreshError = error.localizedDescription
                store.lastError = error.localizedDescription
            }
        }
    }

    private func cancelSceneRollingMemoryRefresh() {
        sceneRollingMemoryTask?.cancel()
        sceneRollingMemoryTask = nil
    }

    private func refreshChapterRollingMemory(from sourceText: String) {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return }

        cancelChapterRollingMemoryRefresh()
        chapterRollingMemoryRefreshError = ""

        chapterRollingMemoryTask = Task { @MainActor in
            defer {
                chapterRollingMemoryTask = nil
            }

            do {
                let refreshed = try await store.refreshSelectedChapterRollingMemory(from: trimmedSource)
                chapterRollingMemoryDraft = refreshed
            } catch is CancellationError {
                return
            } catch {
                chapterRollingMemoryRefreshError = error.localizedDescription
                store.lastError = error.localizedDescription
            }
        }
    }

    private func refreshChapterRollingMemory(
        fromSceneSource source: AppStore.ChapterRollingMemorySceneSource
    ) {
        cancelChapterRollingMemoryRefresh()
        chapterRollingMemoryRefreshError = ""

        chapterRollingMemoryTask = Task { @MainActor in
            defer {
                chapterRollingMemoryTask = nil
            }

            do {
                let refreshed = try await store.refreshSelectedChapterRollingMemoryFromScenes(
                    source
                ) { partialMemory, _, _ in
                    guard isChapterRollingMemorySheetPresented else { return }
                    chapterRollingMemoryDraft = partialMemory
                }
                chapterRollingMemoryDraft = refreshed
            } catch is CancellationError {
                return
            } catch {
                chapterRollingMemoryRefreshError = error.localizedDescription
                store.lastError = error.localizedDescription
            }
        }
    }

    private func cancelChapterRollingMemoryRefresh() {
        chapterRollingMemoryTask?.cancel()
        chapterRollingMemoryTask = nil
    }

    private func rebuildSelectedStoryMemory() {
        cancelStoryMemoryRefresh()
        storyMemoryError = ""

        storyMemoryTask = Task { @MainActor in
            defer {
                storyMemoryTask = nil
            }

            do {
                _ = try await store.rebuildSelectedSceneStoryMemory()
            } catch is CancellationError {
                return
            } catch {
                storyMemoryError = error.localizedDescription
                store.lastError = error.localizedDescription
            }
        }
    }

    private func rebuildProjectStoryMemory() {
        cancelStoryMemoryRefresh()
        storyMemoryError = ""

        storyMemoryTask = Task { @MainActor in
            defer {
                storyMemoryTask = nil
            }

            do {
                try await store.rebuildAllStoryMemory()
            } catch is CancellationError {
                return
            } catch {
                storyMemoryError = error.localizedDescription
                store.lastError = error.localizedDescription
            }
        }
    }

    private func cancelStoryMemoryRefresh() {
        storyMemoryTask?.cancel()
        storyMemoryTask = nil
    }

    private func clearCurrentScope() {
        switch scope {
        case .scene:
            store.updateSelectedSceneSummary("")
        case .chapter:
            store.updateSelectedChapterSummary("")
        }
    }
}

private struct AutoStoryMemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    let sceneSummary: String
    let sceneFacts: [String]
    let sceneOpenThreads: [String]
    let sceneUpdatedAt: Date?
    let chapterSummary: String
    let chapterOpenThreads: [String]
    let chapterUpdatedAt: Date?
    let projectSummary: String
    let projectOpenThreads: [String]
    let projectUpdatedAt: Date?
    let relevantKnowledge: String
    let isUpdating: Bool
    let updateErrorMessage: String?
    let onRebuildScene: () -> Void
    let onRebuildProject: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto Story Memory")
                        .font(.title3.weight(.semibold))
                    Text("\(store.storyKnowledgeNodeCount) active nodes • \(store.storyKnowledgeEdgeCount) active edges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(store.storyKnowledgePendingNodeCount) node suggestions • \(store.storyKnowledgePendingEdgeCount) edge suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section(
                        title: "Project Memory",
                        body: projectSummary,
                        updatedAt: projectUpdatedAt
                    )

                    bulletSection(
                        title: "Project Threads",
                        items: projectOpenThreads
                    )

                    section(
                        title: "Chapter Memory",
                        body: chapterSummary,
                        updatedAt: chapterUpdatedAt
                    )

                    bulletSection(
                        title: "Chapter Threads",
                        items: chapterOpenThreads
                    )

                    section(
                        title: "Scene Memory",
                        body: sceneSummary,
                        updatedAt: sceneUpdatedAt
                    )

                    bulletSection(
                        title: "Scene Facts",
                        items: sceneFacts
                    )

                    bulletSection(
                        title: "Scene Open Threads",
                        items: sceneOpenThreads
                    )

                    section(
                        title: "Relevant Knowledge",
                        body: relevantKnowledge,
                        updatedAt: nil,
                        monospaced: true
                    )

                    pendingNodeSection()

                    pendingEdgeSection()
                }
                .padding(12)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Rebuild Scene") {
                    onRebuildScene()
                }
                .disabled(isUpdating)

                Button("Rebuild Project") {
                    onRebuildProject()
                }
                .disabled(isUpdating)

                Spacer(minLength: 0)

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isUpdating)
            }
            .padding(12)

            if let updateErrorMessage, !updateErrorMessage.isEmpty {
                Text(updateErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    @ViewBuilder
    private func section(
        title: String,
        body: String,
        updatedAt: Date?,
        monospaced: Bool = false
    ) -> some View {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                if let updatedAt {
                    Text(Self.timestampFormatter.string(from: updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if trimmed.isEmpty {
                Text("No memory available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(trimmed)
                    .font(monospaced ? .system(.body, design: .monospaced) : .body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func bulletSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            if items.isEmpty {
                Text("None.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { entry in
                        Text("- \(entry.element)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pendingNodeSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Node Suggestions")
                .font(.headline)

            if store.storyKnowledgePendingReviewNodes.isEmpty {
                Text("No inferred nodes awaiting review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.storyKnowledgePendingReviewNodes.prefix(12)) { node in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(node.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(node.kind.rawValue.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Text(confidenceLabel(node.confidence))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if !node.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(node.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            if !node.aliases.isEmpty {
                                Text("Aliases: \(node.aliases.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            HStack(spacing: 8) {
                                Button("Promote to Compendium") {
                                    store.promoteStoryKnowledgeNodeToCompendium(node.id)
                                }
                                .disabled(isUpdating)

                                Button("Reject", role: .destructive) {
                                    store.rejectStoryKnowledgeNode(node.id)
                                }
                                .disabled(isUpdating)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pendingEdgeSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edge Suggestions")
                .font(.headline)

            if store.storyKnowledgePendingReviewEdges.isEmpty {
                Text("No inferred edges awaiting review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.storyKnowledgePendingReviewEdges.prefix(16)) { edge in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(store.storyKnowledgeEdgeDisplayLabel(edge))
                                    .font(.subheadline.weight(.semibold))
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                                Text(confidenceLabel(edge.confidence))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if !edge.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(edge.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            HStack(spacing: 8) {
                                Button("Accept") {
                                    store.acceptStoryKnowledgeEdge(edge.id)
                                }
                                .disabled(isUpdating)

                                Button("Reject", role: .destructive) {
                                    store.rejectStoryKnowledgeEdge(edge.id)
                                }
                                .disabled(isUpdating)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))%"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct SceneRollingMemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSummaryEditorFocused: Bool

    let sceneTitle: String
    let updatedAt: Date?
    @Binding var draftSummary: String
    let canUpdateFromSummaryText: Bool
    let canUpdateFromFullSceneText: Bool
    let isUpdating: Bool
    let updateErrorMessage: String?
    let onSave: () -> Void
    let onClear: () -> Void
    let onUpdateFromSummaryText: () -> Void
    let onUpdateFromFullSceneText: () -> Void

    private var canRunAnyUpdate: Bool {
        canUpdateFromSummaryText || canUpdateFromFullSceneText
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scene Rolling Memory")
                        .font(.title3.weight(.semibold))
                    Text(sceneTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let updatedAt {
                    Text("Updated \(Self.timestampFormatter.string(from: updatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            TextEditor(text: $draftSummary)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .focused($isSummaryEditorFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 8) {
                Menu("Update...") {
                    Button("From Scene Summary") {
                        onUpdateFromSummaryText()
                    }
                    .disabled(!canUpdateFromSummaryText || isUpdating)

                    Button("From Full Scene Text") {
                        onUpdateFromFullSceneText()
                    }
                    .disabled(!canUpdateFromFullSceneText || isUpdating)
                }
                .disabled(!canRunAnyUpdate || isUpdating)

                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)

                Button("Clear", role: .destructive) {
                    onClear()
                    dismiss()
                }
                .disabled(isUpdating)

                Button("Cancel") {
                    dismiss()
                }
                .disabled(isUpdating)

                Button("Save") {
                    onSave()
                    dismiss()
                }
                .disabled(isUpdating)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)

            if let updateErrorMessage, !updateErrorMessage.isEmpty {
                Text(updateErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .frame(minWidth: 560, minHeight: 380)
        .onAppear {
            DispatchQueue.main.async {
                isSummaryEditorFocused = true
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ChapterRollingMemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSummaryEditorFocused: Bool

    let chapterTitle: String
    let updatedAt: Date?
    @Binding var draftSummary: String
    let canUpdateFromChapterSummary: Bool
    let canUpdateFromCurrentSceneText: Bool
    let canUpdateFromFullChapterText: Bool
    let canUpdateFromUpToSelectedSceneText: Bool
    let isUpdating: Bool
    let updateErrorMessage: String?
    let onSave: () -> Void
    let onClear: () -> Void
    let onUpdateFromChapterSummary: () -> Void
    let onUpdateFromCurrentSceneText: () -> Void
    let onUpdateFromFullChapterText: () -> Void
    let onUpdateFromUpToSelectedSceneText: () -> Void

    private var canRunAnyUpdate: Bool {
        canUpdateFromChapterSummary
            || canUpdateFromCurrentSceneText
            || canUpdateFromFullChapterText
            || canUpdateFromUpToSelectedSceneText
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Chapter Rolling Memory")
                        .font(.title3.weight(.semibold))
                    Text(chapterTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let updatedAt {
                    Text("Updated \(Self.timestampFormatter.string(from: updatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            TextEditor(text: $draftSummary)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .focused($isSummaryEditorFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 8) {
                Menu("Update...") {
                    Button("From Chapter Summary") {
                        onUpdateFromChapterSummary()
                    }
                    .disabled(!canUpdateFromChapterSummary || isUpdating)

                    Button("From Current Scene Text") {
                        onUpdateFromCurrentSceneText()
                    }
                    .disabled(!canUpdateFromCurrentSceneText || isUpdating)

                    Button("From Chapter Text Up to Selected Scene") {
                        onUpdateFromUpToSelectedSceneText()
                    }
                    .disabled(!canUpdateFromUpToSelectedSceneText || isUpdating)

                    Button("From Full Chapter Text") {
                        onUpdateFromFullChapterText()
                    }
                    .disabled(!canUpdateFromFullChapterText || isUpdating)
                }
                .disabled(!canRunAnyUpdate || isUpdating)

                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)

                Button("Clear", role: .destructive) {
                    onClear()
                    dismiss()
                }
                .disabled(isUpdating)

                Button("Cancel") {
                    dismiss()
                }
                .disabled(isUpdating)

                Button("Save") {
                    onSave()
                    dismiss()
                }
                .disabled(isUpdating)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)

            if let updateErrorMessage, !updateErrorMessage.isEmpty {
                Text(updateErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .frame(minWidth: 560, minHeight: 380)
        .onAppear {
            DispatchQueue.main.async {
                isSummaryEditorFocused = true
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
