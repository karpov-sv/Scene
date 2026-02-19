import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    struct PromptImportReport {
        let importedCount: Int
        let skippedCount: Int
    }

    struct CompendiumImportReport {
        let importedCount: Int
        let skippedCount: Int
    }

    private enum DataExchangeError: LocalizedError {
        case projectNotOpen
        case invalidPayloadType(expected: String, actual: String)
        case invalidEPUB(String)
        case checkpointSceneNotFoundInCheckpoint
        case checkpointSceneNotFoundInProject

        var errorDescription: String? {
            switch self {
            case .projectNotOpen:
                return "No project is currently open."
            case let .invalidPayloadType(expected, actual):
                return "Invalid import file type '\(actual)'. Expected '\(expected)'."
            case let .invalidEPUB(message):
                return "Invalid EPUB: \(message)"
            case .checkpointSceneNotFoundInCheckpoint:
                return "Selected scene does not exist in that checkpoint."
            case .checkpointSceneNotFoundInProject:
                return "Selected scene does not exist in the current project."
            }
        }
    }

    private struct PromptTransferEnvelope: Codable {
        var version: String
        var type: String
        var exportedAt: Date
        var prompts: [PromptTransferRecord]
    }

    private struct PromptTransferRecord: Codable {
        var templateID: UUID?
        var category: String
        var title: String
        var userTemplate: String
        var systemTemplate: String
    }

    private struct CompendiumTransferEnvelope: Codable {
        var version: String
        var type: String
        var exportedAt: Date
        var entries: [CompendiumTransferRecord]
    }

    private struct CompendiumTransferRecord: Codable {
        var category: String
        var title: String
        var body: String
        var tags: [String]
    }

    private struct ProjectTransferEnvelope: Codable {
        var version: String
        var type: String
        var exportedAt: Date
        var project: StoryProject
    }

    private struct EPUBManifestItem {
        var id: String
        var href: String
        var mediaType: String
        var properties: String?
    }

    private struct EPUBPackageDescriptor {
        var title: String
        var metadata: ProjectMetadata
        var opfURL: URL
        var packageBaseURL: URL
        var manifestByID: [String: EPUBManifestItem]
        var spineItemIDs: [String]
    }

    private struct EPUBParsedScene {
        var title: String
        var content: String
    }

    private struct EPUBSceneBuilder {
        var title: String
        var paragraphs: [String]
    }

    private struct EPUBParsedChapter {
        var title: String
        var scenes: [EPUBParsedScene]
    }

    private static let transferVersion = "1.0"
    private static let promptTransferType = "scene-prompts"
    private static let compendiumTransferType = "scene-compendium"
    private static let projectTransferType = "scene-project"
    private static let builtInPromptIDs = Set(PromptTemplate.builtInTemplates.map(\.id))
    private static let proseSceneTailChars = 2400
    private static let rewriteSceneContextChars = 2200
    private static let summarySourceChars = 2800
    private static let workshopSceneTailChars = 1800
    private static let rollingWorkshopMemoryMinDeltaMessages = 4
    private static let rollingWorkshopMemoryDeltaWindow = 18
    private static let rollingWorkshopMemoryMaxChars = 3200
    private static let rollingSceneMemoryMaxChars = 2200
    private static let rollingChapterMemoryMaxChars = 2600
    private static let rollingSceneMemorySourceChars = 12000
    private static let rollingChapterMemorySourceChars = 18000
    private static let rollingChapterMemorySceneChunkChars = 6000
    private static let maxVisibleTaskToasts = 4
    private static let epubAuxDocumentKeepThresholdChars = 1200
    private static let epubNonBodyNameMarkers: [String] = [
        "cover",
        "titlepage",
        "title-page",
        "copyright",
        "imprint",
        "toc",
        "tableofcontents",
        "contents",
        "nav",
        "navigation",
        "colophon",
        "about",
        "credits"
    ]
    private static let epubNotesNameMarkers: [String] = [
        "footnote",
        "footnotes",
        "endnote",
        "endnotes",
        "notes"
    ]

    private static let transferEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let transferDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    struct SceneLocation {
        let chapterIndex: Int
        let sceneIndex: Int
    }

    enum ChapterRollingMemorySceneSource {
        case currentScene
        case upToSelectedScene
        case fullChapter
    }

    struct WorkshopPayloadPreview: Identifiable {
        let id: UUID = UUID()
        let providerLabel: String
        let endpointURL: String?
        let method: String?
        let headers: [AIRequestPreview.Header]
        let bodyJSON: String
        let bodyHumanReadable: String
        let notes: [String]
    }

    struct PromptTemplateRenderPreview: Identifiable {
        let id: UUID = UUID()
        let title: String
        let category: PromptCategory
        let renderedUserPrompt: String
        let resolvedSystemPrompt: String
        let notes: [String]
        let warnings: [String]
    }

    struct ProjectCheckpointSummary: Identifiable, Equatable {
        let id: String
        let fileName: String
        let createdAt: Date
    }

    struct SceneCheckpointSnapshot: Identifiable, Equatable {
        let id: String
        let checkpointFileName: String
        let checkpointCreatedAt: Date
        let sceneContent: String
        let sceneContentRTFData: Data?
    }

    struct CheckpointRestoreOptions: Equatable {
        var includeText: Bool = true
        var includeSummaries: Bool = true
        var includeNotes: Bool = true
        var includeCompendium: Bool = true
        var includeTemplates: Bool = true
        var includeSettings: Bool = true
        var includeWorkshop: Bool = true
        var includeInputHistory: Bool = true
        var includeSceneContext: Bool = true
        var restoreDeletedEntries: Bool = false
        var deleteEntriesNotInCheckpoint: Bool = false

        static let `default` = CheckpointRestoreOptions()

        var isNoOp: Bool {
            !includeText
                && !includeSummaries
                && !includeNotes
                && !includeCompendium
                && !includeTemplates
                && !includeSettings
                && !includeWorkshop
                && !includeInputHistory
                && !includeSceneContext
        }
    }

    struct BuiltInPromptRefreshResult {
        let updatedCount: Int
        let addedCount: Int
    }

    struct SceneSearchResult: Identifiable, Equatable {
        let id: UUID
        let chapterID: UUID
        let sceneID: UUID
        let chapterTitle: String
        let sceneTitle: String
        let location: Int
        let length: Int
        let snippet: String

        init(
            id: UUID = UUID(),
            chapterID: UUID,
            sceneID: UUID,
            chapterTitle: String,
            sceneTitle: String,
            location: Int,
            length: Int,
            snippet: String
        ) {
            self.id = id
            self.chapterID = chapterID
            self.sceneID = sceneID
            self.chapterTitle = chapterTitle
            self.sceneTitle = sceneTitle
            self.location = location
            self.length = length
            self.snippet = snippet
        }
    }

    enum GlobalSearchScope: String, CaseIterable, Identifiable {
        case all
        case scene
        case project
        case compendium
        case summaries
        case notes
        case chats

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:
                return "All"
            case .scene:
                return "Scene"
            case .project:
                return "Project"
            case .compendium:
                return "Compendium"
            case .summaries:
                return "Summaries"
            case .notes:
                return "Notes"
            case .chats:
                return "Chats"
            }
        }
    }

    struct GlobalSearchResult: Identifiable, Equatable {
        enum Kind: String, Equatable {
            case scene
            case compendium
            case sceneSummary
            case chapterSummary
            case projectNote
            case chapterNote
            case sceneNote
            case chatMessage
        }

        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        let snippet: String
        let chapterID: UUID?
        let sceneID: UUID?
        let compendiumEntryID: UUID?
        let workshopSessionID: UUID?
        let workshopMessageID: UUID?
        let location: Int?
        let length: Int?
        var isCompendiumTitleMatch: Bool = false
    }

    struct SceneSearchSelectionRequest: Equatable {
        let requestID: UUID = UUID()
        let sceneID: UUID
        let location: Int
        let length: Int
    }

    struct WorkshopMessageRevealRequest: Equatable {
        let requestID: UUID = UUID()
        let sessionID: UUID
        let messageID: UUID
    }

    struct PanelTextRevealRequest: Equatable {
        let requestID: UUID = UUID()
        let location: Int
        let length: Int
    }

    struct SceneReplaceRequest: Equatable {
        let requestID: UUID = UUID()
        let sceneID: UUID
        let location: Int
        let length: Int
        let query: String
        let replacement: String
        let options: NSString.CompareOptions
    }

    struct SceneReplaceAllRequest: Equatable {
        let requestID: UUID = UUID()
        let sceneID: UUID
        let query: String
        let replacement: String
        let options: NSString.CompareOptions
    }

    struct ProseGenerationCandidate: Identifiable, Equatable {
        enum Status: String, Equatable {
            case queued
            case running
            case completed
            case failed
            case cancelled

            var isTerminal: Bool {
                switch self {
                case .queued, .running:
                    return false
                case .completed, .failed, .cancelled:
                    return true
                }
            }
        }

        let id: UUID
        let model: String
        var status: Status
        var text: String
        var usage: TokenUsage?
        var errorMessage: String?
        var elapsedSeconds: Double?
    }

    struct ProseGenerationReviewState: Identifiable, Equatable {
        let id: UUID
        var beat: String
        var sceneTitle: String
        var promptTitle: String
        var renderWarnings: [String]
        var candidates: [ProseGenerationCandidate]
        var startedAt: Date
        var isRunning: Bool

        var completedCount: Int {
            candidates.filter { $0.status.isTerminal }.count
        }

        var successCount: Int {
            candidates.filter { $0.status == .completed }.count
        }
    }

    private struct PromptRequestBuildResult {
        let request: TextGenerationRequest
        let renderWarnings: [String]
    }

    private struct SceneContextSections {
        let combined: String
        let compendium: String
        let sceneSummaries: String
        let chapterSummaries: String
    }

    private struct ProseGenerationSessionContext {
        let reviewID: UUID
        let sceneID: UUID
        let beat: String
    }

    private struct ProseCandidateRequestInput {
        let candidateID: UUID
        let model: String
        let request: TextGenerationRequest
    }

    private struct ProseCandidateRunResult {
        let candidateID: UUID
        let request: TextGenerationRequest
        let text: String?
        let usage: TokenUsage?
        let errorMessage: String?
        let cancelled: Bool
        let elapsedSeconds: Double
    }

    private struct PromptPreviewSceneContext {
        let sceneID: UUID?
        let sceneTitle: String
        let chapterTitle: String
        let sceneContent: String
        let note: String?
    }

    private struct ChapterMemorySourceChunk {
        let label: String
        let text: String
    }

    struct TaskNotificationToast: Identifiable, Equatable {
        enum Style: Equatable {
            case progress
            case success
            case info
            case warning
            case error
            case cancelled
        }

        let id: UUID
        var message: String
        var style: Style
        var createdAt: Date
    }

    @Published private(set) var project: StoryProject
    @Published private(set) var isProjectOpen: Bool = false
    @Published private(set) var currentProjectURL: URL?

    @Published var selectedChapterID: UUID?
    @Published var selectedSceneID: UUID?
    @Published var selectedCompendiumID: UUID?
    @Published private(set) var sceneRichTextRefreshID: UUID = UUID()

    @Published var selectedWorkshopSessionID: UUID?
    @Published var workshopInput: String = ""
    @Published var workshopIsGenerating: Bool = false
    @Published var workshopStatus: String = ""
    @Published var workshopUseSceneContext: Bool = true
    @Published var workshopUseCompendiumContext: Bool = true
    @Published private(set) var workshopLiveUsage: TokenUsage?
    private var workshopStreamingLastPublishDate: Date = .distantPast
    private let workshopStreamingPublishInterval: TimeInterval = 0.05

    @Published var beatInput: String = ""
    @Published var isGenerating: Bool = false
    @Published var generationStatus: String = ""
    @Published private(set) var proseLiveUsage: TokenUsage?
    @Published var proseGenerationReview: ProseGenerationReviewState?
    @Published var lastError: String?
    @Published private(set) var availableRemoteModels: [String] = []
    @Published var isDiscoveringModels: Bool = false
    @Published var modelDiscoveryStatus: String = ""
    @Published var globalSearchQuery: String = ""
    @Published var globalSearchScope: GlobalSearchScope = .all
    @Published private(set) var globalSearchResults: [GlobalSearchResult] = []
    @Published private(set) var selectedGlobalSearchResultID: String?
    @Published private(set) var globalSearchFocusRequestID: UUID = UUID()
    @Published var isGlobalSearchVisible: Bool = false
    @Published private(set) var lastGlobalSearchQuery: String = ""
    @Published private(set) var lastGlobalSearchScope: GlobalSearchScope = .all
    @Published var replaceText: String = ""
    @Published var isReplaceMode: Bool = false
    @Published private(set) var pendingSceneSearchSelection: SceneSearchSelectionRequest?
    @Published private(set) var pendingWorkshopMessageReveal: WorkshopMessageRevealRequest?
    @Published private(set) var pendingCompendiumTextReveal: PanelTextRevealRequest?
    @Published private(set) var pendingSummaryTextReveal: PanelTextRevealRequest?
    @Published private(set) var pendingNotesTextReveal: PanelTextRevealRequest?
    @Published private(set) var pendingSceneReplace: SceneReplaceRequest?
    @Published private(set) var pendingSceneReplaceAll: SceneReplaceAllRequest?
    @Published private(set) var projectCheckpoints: [ProjectCheckpointSummary] = []

    @Published private(set) var sceneEditorFocusRequestID: UUID = UUID()
    @Published private(set) var beatInputFocusRequestID: UUID = UUID()
    @Published private(set) var workshopInputFocusRequestID: UUID = UUID()
    @Published private(set) var sceneHistorySheetRequestID: UUID = UUID()
    @Published private(set) var requestedSceneHistorySceneID: UUID?

    @Published var showingSettings: Bool = false
    @Published private(set) var taskNotificationToasts: [TaskNotificationToast] = []

    // Per-document UI layout state (avoids global @AppStorage cross-window contamination)
    @Published var workspaceTab: String = "writing"
    @Published var writingSidePanel: String = "compendium"
    @Published var isGenerationPanelVisible: Bool = true

    private let persistence: ProjectPersistence
    private let openAIService: OpenAICompatibleAIService
    private let anthropicService: AnthropicAIService
    private let promptRenderer: PromptRenderer
    private let isDocumentBacked: Bool
    private var documentChangeHandler: ((StoryProject) -> Void)?

    private var autosaveTask: Task<Void, Never>?
    private var modelDiscoveryTask: Task<Void, Never>?
    private var workshopRequestTask: Task<Void, Never>?
    private var workshopRollingMemoryTask: Task<Void, Never>?
    private var proseRequestTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    private var documentSaveInProgress: Bool = false
    private var pendingDocumentSaveRequest: Bool = false
    private var proseGenerationSessionContext: ProseGenerationSessionContext?
    private var toastDismissTasks: [UUID: Task<Void, Never>] = [:]

    init(
        persistence: ProjectPersistence = .shared,
        openAIService: OpenAICompatibleAIService = OpenAICompatibleAIService(),
        anthropicService: AnthropicAIService = AnthropicAIService(),
        promptRenderer: PromptRenderer = PromptRenderer()
    ) {
        self.persistence = persistence
        self.openAIService = openAIService
        self.anthropicService = anthropicService
        self.promptRenderer = promptRenderer
        self.isDocumentBacked = false
        self.documentChangeHandler = nil

        self.project = StoryProject.starter()

        if let lastProjectURL = persistence.loadLastOpenedProjectURL() {
            do {
                let loadedProject = try persistence.loadProject(at: lastProjectURL)
                applyLoadedProject(loadedProject, from: lastProjectURL, rememberAsLastOpened: true)
            } catch {
                setClosedProjectState(clearLastOpenedReference: true)
                lastError = "Failed to open last project: \(error.localizedDescription)"
            }
        } else {
            setClosedProjectState(clearLastOpenedReference: false)
        }
    }

    init(
        documentProject: StoryProject,
        projectURL: URL?,
        persistence: ProjectPersistence = .shared,
        openAIService: OpenAICompatibleAIService = OpenAICompatibleAIService(),
        anthropicService: AnthropicAIService = AnthropicAIService(),
        promptRenderer: PromptRenderer = PromptRenderer()
    ) {
        self.persistence = persistence
        self.openAIService = openAIService
        self.anthropicService = anthropicService
        self.promptRenderer = promptRenderer
        self.isDocumentBacked = true
        self.documentChangeHandler = nil
        self.project = documentProject
        self.currentProjectURL = projectURL?.standardizedFileURL
        self.isProjectOpen = true

        ensureProjectBaseline()

        selectedSceneID = project.selectedSceneID ?? project.chapters.first?.scenes.first?.id
        if let selectedSceneID,
           let location = sceneLocation(for: selectedSceneID) {
            selectedChapterID = project.chapters[location.chapterIndex].id
        } else {
            selectedChapterID = project.chapters.first?.id
        }
        selectedCompendiumID = project.compendium.first?.id
        selectedWorkshopSessionID = project.selectedWorkshopSessionID ?? project.workshopSessions.first?.id
        ensureValidSelections()

        if project.settings.provider.supportsModelDiscovery {
            scheduleModelDiscovery(immediate: true)
        }

        refreshProjectCheckpoints()
    }

    deinit {
        autosaveTask?.cancel()
        modelDiscoveryTask?.cancel()
        workshopRequestTask?.cancel()
        workshopRollingMemoryTask?.cancel()
        proseRequestTask?.cancel()
        for task in toastDismissTasks.values {
            task.cancel()
        }
        toastDismissTasks.removeAll()
    }

    // MARK: - Read APIs

    var currentProjectPathDisplay: String {
        currentProjectURL?.path ?? "Unsaved project"
    }

    var currentProjectName: String {
        if let currentProjectURL {
            return currentProjectURL.deletingPathExtension().lastPathComponent
        }

        let trimmedTitle = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled Project" : trimmedTitle
    }

    var canManageProjectCheckpoints: Bool {
        isProjectOpen && currentProjectURL != nil
    }

    var chapters: [Chapter] {
        isProjectOpen ? project.chapters : []
    }

    var workshopSessions: [WorkshopSession] {
        isProjectOpen ? project.workshopSessions : []
    }

    var prosePrompts: [PromptTemplate] {
        guard isProjectOpen else { return [] }
        return project.prompts.filter { $0.category == .prose }
    }

    var rewritePrompts: [PromptTemplate] {
        guard isProjectOpen else { return [] }
        return project.prompts.filter { $0.category == .rewrite }
    }

    var summaryPrompts: [PromptTemplate] {
        guard isProjectOpen else { return [] }
        return project.prompts.filter { $0.category == .summary }
    }

    var workshopPrompts: [PromptTemplate] {
        guard isProjectOpen else { return [] }
        return project.prompts.filter { $0.category == .workshop }
    }

    func prompts(in category: PromptCategory) -> [PromptTemplate] {
        guard isProjectOpen else { return [] }
        return project.prompts.filter { $0.category == category }
    }

    func mentionSuggestions(
        for trigger: MentionTrigger,
        query: String,
        limit: Int = 12
    ) -> [MentionSuggestion] {
        guard isProjectOpen else { return [] }
        let normalizedQuery = MentionParsing.normalize(query)

        switch trigger {
        case .tag:
            var frequencies: [String: (label: String, count: Int)] = [:]
            for entry in project.compendium {
                var labelsByKey: [String: String] = [:]
                for tag in entry.tags {
                    let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = MentionParsing.normalize(cleaned)
                    guard !key.isEmpty else { continue }
                    labelsByKey[key] = labelsByKey[key] ?? cleaned
                }

                let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let titleKey = MentionParsing.normalize(title)
                if !titleKey.isEmpty {
                    labelsByKey[titleKey] = labelsByKey[titleKey] ?? title
                }

                for (key, label) in labelsByKey {
                    if var existing = frequencies[key] {
                        existing.count += 1
                        frequencies[key] = existing
                    } else {
                        frequencies[key] = (label: label, count: 1)
                    }
                }
            }

            return frequencies
                .filter { normalizedQuery.isEmpty || $0.key.contains(normalizedQuery) }
                .sorted {
                    if $0.value.count != $1.value.count {
                        return $0.value.count > $1.value.count
                    }
                    return $0.value.label.localizedCaseInsensitiveCompare($1.value.label) == .orderedAscending
                }
                .prefix(limit)
                .map { key, value in
                    MentionSuggestion(
                        id: "tag:\(key)",
                        trigger: .tag,
                        label: value.label,
                        subtitle: "\(value.count) entr\(value.count == 1 ? "y" : "ies")",
                        insertion: value.label.contains { $0.isWhitespace }
                            ? "@[\(value.label)] "
                            : "@\(value.label) "
                    )
                }

        case .scene:
            struct SceneSuggestionCandidate {
                let id: UUID
                let chapterTitle: String
                let sceneTitle: String
                let inSelectedChapter: Bool
                let hasSummary: Bool
            }

            var candidates: [SceneSuggestionCandidate] = []
            for chapter in project.chapters {
                let chapterTitleRaw = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let chapterTitle = chapterTitleRaw.isEmpty ? "Untitled Chapter" : chapterTitleRaw
                let inSelectedChapter = chapter.id == selectedChapterID

                for scene in chapter.scenes {
                    let sceneTitleRaw = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sceneTitle = sceneTitleRaw.isEmpty ? "Untitled Scene" : sceneTitleRaw
                    let key = MentionParsing.normalize(sceneTitle)
                    guard normalizedQuery.isEmpty || key.contains(normalizedQuery) else { continue }

                    candidates.append(
                        SceneSuggestionCandidate(
                            id: scene.id,
                            chapterTitle: chapterTitle,
                            sceneTitle: sceneTitle,
                            inSelectedChapter: inSelectedChapter,
                            hasSummary: !scene.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    )
                }
            }

            return candidates
                .sorted {
                    if $0.inSelectedChapter != $1.inSelectedChapter {
                        return $0.inSelectedChapter && !$1.inSelectedChapter
                    }
                    if $0.sceneTitle.caseInsensitiveCompare($1.sceneTitle) != .orderedSame {
                        return $0.sceneTitle.localizedCaseInsensitiveCompare($1.sceneTitle) == .orderedAscending
                    }
                    return $0.chapterTitle.localizedCaseInsensitiveCompare($1.chapterTitle) == .orderedAscending
                }
                .prefix(limit)
                .map { item in
                    MentionSuggestion(
                        id: "scene:\(item.id.uuidString)",
                        trigger: .scene,
                        label: item.sceneTitle,
                        subtitle: item.hasSummary ? item.chapterTitle : "\(item.chapterTitle) • no summary",
                        insertion: item.sceneTitle.contains { $0.isWhitespace }
                            ? "#[\(item.sceneTitle)] "
                            : "#\(item.sceneTitle) "
                    )
                }
        }
    }

    var selectedScene: Scene? {
        guard isProjectOpen else { return nil }
        guard let selectedSceneID, let location = sceneLocation(for: selectedSceneID) else {
            return nil
        }
        return project.chapters[location.chapterIndex].scenes[location.sceneIndex]
    }

    var selectedChapter: Chapter? {
        guard isProjectOpen else { return nil }
        guard let selectedChapterID,
              let chapterIndex = chapterIndex(for: selectedChapterID) else {
            return nil
        }
        return project.chapters[chapterIndex]
    }

    var selectedCompendiumEntry: CompendiumEntry? {
        guard isProjectOpen else { return nil }
        guard let selectedCompendiumID, let index = compendiumIndex(for: selectedCompendiumID) else {
            return nil
        }
        return project.compendium[index]
    }

    var selectedWorkshopSession: WorkshopSession? {
        guard isProjectOpen else { return nil }
        guard let selectedWorkshopSessionID,
              let index = workshopSessionIndex(for: selectedWorkshopSessionID) else {
            return nil
        }
        return project.workshopSessions[index]
    }

    var activeProsePrompt: PromptTemplate? {
        guard isProjectOpen else { return nil }
        return resolvedActivePrompt(
            for: .prose,
            selectedID: project.selectedProsePromptID
        )
    }

    var activeWorkshopPrompt: PromptTemplate? {
        guard isProjectOpen else { return nil }
        return resolvedActivePrompt(
            for: .workshop,
            selectedID: project.selectedWorkshopPromptID
        )
    }

    var activeRewritePrompt: PromptTemplate? {
        guard isProjectOpen else { return nil }
        return resolvedActivePrompt(
            for: .rewrite,
            selectedID: project.selectedRewritePromptID
        )
    }

    var activeSummaryPrompt: PromptTemplate? {
        guard isProjectOpen else { return nil }
        return resolvedActivePrompt(
            for: .summary,
            selectedID: project.selectedSummaryPromptID
        )
    }

    private func resolvedActivePrompt(for category: PromptCategory, selectedID: UUID?) -> PromptTemplate? {
        if let selectedID, let index = promptIndex(for: selectedID) {
            return project.prompts[index]
        }

        let defaultID = defaultBuiltInPromptID(for: category)
        if let index = promptIndex(for: defaultID),
           project.prompts[index].category == category {
            return project.prompts[index]
        }

        return project.prompts.first(where: { $0.category == category })
    }

    var workshopInputHistory: [String] {
        guard let selectedWorkshopSessionID else {
            return []
        }
        return project.workshopInputHistoryBySession[selectedWorkshopSessionID.uuidString] ?? []
    }

    var selectedWorkshopRollingMemorySummary: String {
        guard let selectedWorkshopSessionID else { return "" }
        return project.rollingWorkshopMemoryBySession[selectedWorkshopSessionID.uuidString]?.summary ?? ""
    }

    var selectedWorkshopRollingMemoryUpdatedAt: Date? {
        guard let selectedWorkshopSessionID else { return nil }
        return project.rollingWorkshopMemoryBySession[selectedWorkshopSessionID.uuidString]?.updatedAt
    }

    var selectedSceneRollingMemorySummary: String {
        guard let selectedSceneID else { return "" }
        return project.rollingSceneMemoryByScene[selectedSceneID.uuidString]?.summary ?? ""
    }

    var selectedSceneRollingMemoryUpdatedAt: Date? {
        guard let selectedSceneID else { return nil }
        return project.rollingSceneMemoryByScene[selectedSceneID.uuidString]?.updatedAt
    }

    var selectedChapterRollingMemorySummary: String {
        rollingChapterSummary(for: selectedChapterID)
    }

    var selectedChapterRollingMemoryUpdatedAt: Date? {
        guard let selectedChapterID else { return nil }
        guard !rollingChapterSummary(for: selectedChapterID).isEmpty else { return nil }
        return project.rollingChapterMemoryByChapter[selectedChapterID.uuidString]?.updatedAt
    }

    var selectedChapterRollingMemorySourceText: String {
        guard let chapter = selectedChapter else { return "" }
        return chapterSourceText(chapter: chapter, maxChars: Self.rollingChapterMemorySourceChars)
    }

    var selectedChapterRollingMemorySourceTextCurrentScene: String {
        guard let chapter = selectedChapter,
              let selectedSceneID,
              let sceneIndex = chapter.scenes.firstIndex(where: { $0.id == selectedSceneID }) else {
            return ""
        }
        let scene = chapter.scenes[sceneIndex]
        let content = scene.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return "" }
        let labeled = "Scene \(sceneIndex + 1): \(displaySceneTitle(scene))\n\(content)"
        return labeled.count > Self.rollingChapterMemorySourceChars
            ? String(labeled.prefix(Self.rollingChapterMemorySourceChars))
            : labeled
    }

    var selectedChapterRollingMemorySourceTextUpToSelectedScene: String {
        guard let chapter = selectedChapter,
              let selectedSceneID,
              chapter.scenes.contains(where: { $0.id == selectedSceneID }) else {
            return ""
        }
        return chapterSourceText(
            chapter: chapter,
            upToSceneID: selectedSceneID,
            maxChars: Self.rollingChapterMemorySourceChars
        )
    }

    var beatInputHistory: [String] {
        guard let selectedSceneID else {
            return []
        }
        return project.beatInputHistoryByScene[selectedSceneID.uuidString] ?? []
    }

    var canRetryLastWorkshopTurn: Bool {
        guard !workshopIsGenerating else { return false }
        guard let session = selectedWorkshopSession else { return false }
        return session.messages.lastIndex(where: { $0.role == .user }) != nil
    }

    var canDeleteLastWorkshopAssistantMessage: Bool {
        guard !workshopIsGenerating else { return false }
        guard let session = selectedWorkshopSession else { return false }
        return session.messages.lastIndex(where: { $0.role == .assistant }) != nil
    }

    var canDeleteLastWorkshopUserTurn: Bool {
        guard !workshopIsGenerating else { return false }
        guard let session = selectedWorkshopSession else { return false }
        return session.messages.lastIndex(where: { $0.role == .user }) != nil
    }

    var inlineWorkshopUsage: TokenUsage? {
        if workshopIsGenerating {
            return workshopLiveUsage
        }
        return selectedWorkshopSession?.messages.reversed().compactMap(\.usage).first
    }

    var inlineProseUsage: TokenUsage? {
        proseLiveUsage
    }

    func updateGlobalSearchQuery(_ query: String, maxResults: Int = 300) {
        globalSearchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lastGlobalSearchQuery = trimmed
            lastGlobalSearchScope = globalSearchScope
        }
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            refreshGlobalSearchResults(maxResults: maxResults)
        }
    }

    func updateGlobalSearchScope(_ scope: GlobalSearchScope, maxResults: Int = 300) {
        globalSearchScope = scope
        refreshGlobalSearchResults(maxResults: maxResults)
    }

    func requestBeatInputFocus() {
        beatInputFocusRequestID = UUID()
    }

    func focusTextGenerationInput() {
        isGenerationPanelVisible = true
        requestBeatInputFocus()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.requestBeatInputFocus()
        }
    }

    func setGenerationPanelVisible(_ visible: Bool) {
        isGenerationPanelVisible = visible
    }

    func toggleGenerationPanelVisibility() {
        isGenerationPanelVisible.toggle()
    }

    func requestSceneEditorFocus() {
        sceneEditorFocusRequestID = UUID()
    }

    func requestWorkshopInputFocus() {
        workshopInputFocusRequestID = UUID()
    }

    func requestSceneHistory(for sceneID: UUID? = nil) {
        guard let targetSceneID = sceneID ?? selectedSceneID else { return }
        requestedSceneHistorySceneID = targetSceneID
        sceneHistorySheetRequestID = UUID()
    }

    func consumeSceneHistoryRequest() {
        requestedSceneHistorySceneID = nil
    }

    func requestGlobalSearchFocus(scope: GlobalSearchScope, maxResults: Int = 300) {
        isGlobalSearchVisible = true
        updateGlobalSearchScope(scope, maxResults: maxResults)
        globalSearchFocusRequestID = UUID()
    }

    func refreshGlobalSearchResults(maxResults: Int = 300) {
        let previousSelectionID = selectedGlobalSearchResultID
        let refreshed = searchGlobalContent(
            globalSearchQuery,
            scope: globalSearchScope,
            caseSensitive: false,
            maxResults: maxResults
        )
        globalSearchResults = refreshed

        if let previousSelectionID,
           refreshed.contains(where: { $0.id == previousSelectionID }) {
            selectedGlobalSearchResultID = previousSelectionID
        } else {
            selectedGlobalSearchResultID = nil
        }
    }

    func setSelectedGlobalSearchResultID(_ id: String?) {
        selectedGlobalSearchResultID = id
    }

    func dismissGlobalSearch() {
        searchDebounceTask?.cancel()
        isGlobalSearchVisible = false
        globalSearchQuery = ""
        globalSearchResults = []
        selectedGlobalSearchResultID = nil
    }

    func restoreLastSearchIfNeeded() {
        guard globalSearchResults.isEmpty,
              !lastGlobalSearchQuery.isEmpty else { return }
        let restored = searchGlobalContent(
            lastGlobalSearchQuery,
            scope: lastGlobalSearchScope,
            caseSensitive: false,
            maxResults: 300
        )
        globalSearchResults = restored
    }

    func selectedGlobalSearchResult() -> GlobalSearchResult? {
        guard let selectedGlobalSearchResultID else { return nil }
        return globalSearchResults.first(where: { $0.id == selectedGlobalSearchResultID })
    }

    @discardableResult
    func selectNextGlobalSearchResult() -> GlobalSearchResult? {
        selectGlobalSearchResult(step: 1)
    }

    @discardableResult
    func selectPreviousGlobalSearchResult() -> GlobalSearchResult? {
        selectGlobalSearchResult(step: -1)
    }

    // MARK: - Search & Replace

    @discardableResult
    func replaceCurrentSearchMatch(with replacement: String) -> Bool {
        guard let result = selectedGlobalSearchResult(),
              let location = result.location,
              let length = result.length else {
            return false
        }

        let query = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }

        let compareOptions: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        switch result.kind {
        case .chatMessage:
            return false

        case .scene:
            guard let sceneID = result.sceneID else { return false }
            if sceneID == selectedSceneID {
                // Route through the editor for undo support
                pendingSceneReplace = SceneReplaceRequest(
                    sceneID: sceneID,
                    location: location,
                    length: length,
                    query: query,
                    replacement: replacement,
                    options: compareOptions
                )
                // Editor will call didCompleteEditorReplace() which refreshes & advances
                return true
            }
            guard replaceInSceneContent(sceneID: sceneID, at: location, length: length, query: query, replacement: replacement, options: compareOptions) else {
                return false
            }

        case .compendium:
            guard let entryID = result.compendiumEntryID,
                  let index = compendiumIndex(for: entryID) else {
                return false
            }
            if result.isCompendiumTitleMatch {
                let title = project.compendium[index].title
                guard let newTitle = replaceInPlainText(title, at: location, length: length, query: query, replacement: replacement, options: compareOptions) else {
                    return false
                }
                project.compendium[index].title = newTitle
            } else {
                let body = project.compendium[index].body
                guard let newBody = replaceInPlainText(body, at: location, length: length, query: query, replacement: replacement, options: compareOptions) else {
                    return false
                }
                project.compendium[index].body = newBody
            }
            project.compendium[index].updatedAt = .now
            saveProject(debounced: false)

        case .sceneSummary:
            guard let sceneID = result.sceneID,
                  let loc = sceneLocation(for: sceneID) else {
                return false
            }
            let summary = project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].summary
            guard let newSummary = replaceInPlainText(summary, at: location, length: length, query: query, replacement: replacement, options: compareOptions) else {
                return false
            }
            project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].summary = newSummary
            project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].updatedAt = .now
            saveProject(debounced: false)

        case .chapterSummary:
            guard let chapterID = result.chapterID,
                  let ci = chapterIndex(for: chapterID) else {
                return false
            }
            let summary = project.chapters[ci].summary
            guard let newSummary = replaceInPlainText(summary, at: location, length: length, query: query, replacement: replacement, options: compareOptions) else {
                return false
            }
            project.chapters[ci].summary = newSummary
            project.chapters[ci].updatedAt = .now
            saveProject(debounced: false)

        case .projectNote:
            let notes = project.notes
            guard let newNotes = replaceInPlainText(notes, at: location, length: length, query: query, replacement: replacement, options: compareOptions) else {
                return false
            }
            project.notes = newNotes
            saveProject(debounced: false)

        case .chapterNote:
            guard let chapterID = result.chapterID,
                  let ci = chapterIndex(for: chapterID) else {
                return false
            }
            let notes = project.chapters[ci].notes
            guard let newNotes = replaceInPlainText(notes, at: location, length: length, query: query, replacement: replacement, options: compareOptions) else {
                return false
            }
            project.chapters[ci].notes = newNotes
            project.chapters[ci].updatedAt = .now
            saveProject(debounced: false)

        case .sceneNote:
            guard let sceneID = result.sceneID,
                  let loc = sceneLocation(for: sceneID) else {
                return false
            }
            let notes = project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].notes
            guard let newNotes = replaceInPlainText(notes, at: location, length: length, query: query, replacement: replacement, options: compareOptions) else {
                return false
            }
            project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].notes = newNotes
            project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].updatedAt = .now
            saveProject(debounced: false)
        }

        refreshGlobalSearchResults()
        _ = selectNextGlobalSearchResult()
        return true
    }

    func replaceAllSearchMatches(with replacement: String) -> Int {
        let query = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, isProjectOpen else { return 0 }

        let compareOptions: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let scope = globalSearchScope
        var totalCount = 0
        var mutatedOutsideEditor = false

        let shouldReplaceScenes = scope == .all || scope == .scene || scope == .project
        let shouldReplaceCompendium = scope == .all || scope == .compendium
        let shouldReplaceSummaries = scope == .all || scope == .summaries
        let shouldReplaceNotes = scope == .all || scope == .notes

        if shouldReplaceScenes {
            let sceneIDs: [UUID]
            if scope == .scene {
                sceneIDs = selectedSceneID.map { [$0] } ?? []
            } else {
                sceneIDs = project.chapters.flatMap { $0.scenes.map(\.id) }
            }
            for sceneID in sceneIDs {
                if sceneID == selectedSceneID {
                    // Route displayed scene through editor for undo support
                    pendingSceneReplaceAll = SceneReplaceAllRequest(
                        sceneID: sceneID,
                        query: query,
                        replacement: replacement,
                        options: compareOptions
                    )
                    // Count matches in advance for the return value
                    let scene = project.chapters.flatMap(\.scenes).first(where: { $0.id == sceneID })
                    if let content = scene?.content {
                        let ns = content as NSString
                        var start = 0
                        while start < ns.length {
                            let r = ns.range(of: query, options: compareOptions, range: NSRange(location: start, length: ns.length - start))
                            guard r.location != NSNotFound else { break }
                            totalCount += 1
                            start = r.location + max(r.length, 1)
                        }
                    }
                } else {
                    let count = replaceAllInSceneContent(
                        sceneID: sceneID,
                        query: query,
                        replacement: replacement,
                        options: compareOptions
                    )
                    if count > 0 {
                        mutatedOutsideEditor = true
                        totalCount += count
                    }
                }
            }
        }

        if shouldReplaceCompendium {
            for index in project.compendium.indices {
                let (newTitle, titleCount) = replaceAllInPlainText(project.compendium[index].title, query: query, replacement: replacement, options: compareOptions)
                let (newBody, bodyCount) = replaceAllInPlainText(project.compendium[index].body, query: query, replacement: replacement, options: compareOptions)
                let entryCount = titleCount + bodyCount
                if entryCount > 0 {
                    project.compendium[index].title = newTitle
                    project.compendium[index].body = newBody
                    project.compendium[index].updatedAt = .now
                    mutatedOutsideEditor = true
                    totalCount += entryCount
                }
            }
        }

        if shouldReplaceSummaries {
            for ci in project.chapters.indices {
                let (newChapterSummary, csCount) = replaceAllInPlainText(project.chapters[ci].summary, query: query, replacement: replacement, options: compareOptions)
                if csCount > 0 {
                    project.chapters[ci].summary = newChapterSummary
                    project.chapters[ci].updatedAt = .now
                    mutatedOutsideEditor = true
                    totalCount += csCount
                }
                for si in project.chapters[ci].scenes.indices {
                    let (newSceneSummary, ssCount) = replaceAllInPlainText(project.chapters[ci].scenes[si].summary, query: query, replacement: replacement, options: compareOptions)
                    if ssCount > 0 {
                        project.chapters[ci].scenes[si].summary = newSceneSummary
                        project.chapters[ci].scenes[si].updatedAt = .now
                        mutatedOutsideEditor = true
                        totalCount += ssCount
                    }
                }
            }
        }

        if shouldReplaceNotes {
            let (newProjectNotes, pnCount) = replaceAllInPlainText(project.notes, query: query, replacement: replacement, options: compareOptions)
            if pnCount > 0 {
                project.notes = newProjectNotes
                mutatedOutsideEditor = true
                totalCount += pnCount
            }
            for ci in project.chapters.indices {
                let (newChapterNotes, cnCount) = replaceAllInPlainText(project.chapters[ci].notes, query: query, replacement: replacement, options: compareOptions)
                if cnCount > 0 {
                    project.chapters[ci].notes = newChapterNotes
                    project.chapters[ci].updatedAt = .now
                    mutatedOutsideEditor = true
                    totalCount += cnCount
                }
                for si in project.chapters[ci].scenes.indices {
                    let (newSceneNotes, snCount) = replaceAllInPlainText(project.chapters[ci].scenes[si].notes, query: query, replacement: replacement, options: compareOptions)
                    if snCount > 0 {
                        project.chapters[ci].scenes[si].notes = newSceneNotes
                        project.chapters[ci].scenes[si].updatedAt = .now
                        mutatedOutsideEditor = true
                        totalCount += snCount
                    }
                }
            }
        }

        if totalCount > 0 {
            if mutatedOutsideEditor {
                saveProject(debounced: false)
            }
            refreshGlobalSearchResults()
        }

        return totalCount
    }

    // MARK: - Replace Helpers (Private)

    private func replaceInSceneContent(sceneID: UUID, at location: Int, length: Int, query: String, replacement: String, options: NSString.CompareOptions) -> Bool {
        guard let loc = sceneLocation(for: sceneID) else { return false }
        let scene = project.chapters[loc.chapterIndex].scenes[loc.sceneIndex]
        let attributed = makeAttributedSceneContent(plainText: scene.content, richTextData: scene.contentRTFData)

        guard location + length <= attributed.length else { return false }
        let matchRange = NSRange(location: location, length: length)
        let existingText = attributed.mutableString.substring(with: matchRange) as NSString
        guard existingText.range(of: query, options: options).location == 0,
              existingText.length == length else {
            return false
        }

        attributed.replaceCharacters(in: matchRange, with: replacement)

        project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].content = attributed.string
        project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].contentRTFData = makeRTFData(from: attributed)
        project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].updatedAt = .now
        project.chapters[loc.chapterIndex].updatedAt = .now
        project.rollingSceneMemoryByScene.removeValue(forKey: sceneID.uuidString)
        project.rollingChapterMemoryByChapter.removeValue(
            forKey: project.chapters[loc.chapterIndex].id.uuidString
        )

        if selectedSceneID == sceneID {
            sceneRichTextRefreshID = UUID()
        }
        saveProject(debounced: false)
        return true
    }

    private func replaceAllInSceneContent(sceneID: UUID, query: String, replacement: String, options: NSString.CompareOptions) -> Int {
        guard let loc = sceneLocation(for: sceneID) else { return 0 }
        let scene = project.chapters[loc.chapterIndex].scenes[loc.sceneIndex]
        let attributed = makeAttributedSceneContent(plainText: scene.content, richTextData: scene.contentRTFData)

        let count = attributed.mutableString.replaceOccurrences(
            of: query,
            with: replacement,
            options: options,
            range: NSRange(location: 0, length: attributed.mutableString.length)
        )
        guard count > 0 else { return 0 }

        project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].content = attributed.string
        project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].contentRTFData = makeRTFData(from: attributed)
        project.chapters[loc.chapterIndex].scenes[loc.sceneIndex].updatedAt = .now
        project.chapters[loc.chapterIndex].updatedAt = .now
        project.rollingSceneMemoryByScene.removeValue(forKey: sceneID.uuidString)
        project.rollingChapterMemoryByChapter.removeValue(
            forKey: project.chapters[loc.chapterIndex].id.uuidString
        )

        if selectedSceneID == sceneID {
            sceneRichTextRefreshID = UUID()
        }
        return count
    }

    private func replaceInPlainText(_ text: String, at location: Int, length: Int, query: String, replacement: String, options: NSString.CompareOptions) -> String? {
        let nsText = text as NSString
        guard location + length <= nsText.length else { return nil }
        let matchRange = NSRange(location: location, length: length)
        let existing = nsText.substring(with: matchRange) as NSString
        guard existing.range(of: query, options: options).location == 0,
              existing.length == length else {
            return nil
        }
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: matchRange, with: replacement)
        return mutable as String
    }

    private func replaceAllInPlainText(_ text: String, query: String, replacement: String, options: NSString.CompareOptions) -> (String, Int) {
        let mutable = NSMutableString(string: text)
        let count = mutable.replaceOccurrences(
            of: query,
            with: replacement,
            options: options,
            range: NSRange(location: 0, length: mutable.length)
        )
        return (mutable as String, count)
    }

    func revealSceneSearchMatch(
        chapterID: UUID,
        sceneID: UUID,
        location: Int,
        length: Int
    ) {
        guard isProjectOpen else { return }
        selectScene(sceneID, chapterID: chapterID)
        pendingSceneSearchSelection = SceneSearchSelectionRequest(
            sceneID: sceneID,
            location: max(0, location),
            length: max(0, length)
        )
    }

    func consumeSceneSearchSelectionRequest(_ requestID: UUID) {
        guard pendingSceneSearchSelection?.requestID == requestID else { return }
        pendingSceneSearchSelection = nil
    }

    func revealWorkshopMessage(sessionID: UUID, messageID: UUID) {
        pendingWorkshopMessageReveal = WorkshopMessageRevealRequest(
            sessionID: sessionID,
            messageID: messageID
        )
    }

    func consumeWorkshopMessageReveal(_ requestID: UUID) {
        guard pendingWorkshopMessageReveal?.requestID == requestID else { return }
        pendingWorkshopMessageReveal = nil
    }

    func revealCompendiumText(location: Int, length: Int) {
        pendingCompendiumTextReveal = PanelTextRevealRequest(
            location: max(0, location),
            length: max(0, length)
        )
    }

    func consumeCompendiumTextReveal() {
        pendingCompendiumTextReveal = nil
    }

    func revealSummaryText(location: Int, length: Int) {
        pendingSummaryTextReveal = PanelTextRevealRequest(
            location: max(0, location),
            length: max(0, length)
        )
    }

    func consumeSummaryTextReveal() {
        pendingSummaryTextReveal = nil
    }

    func revealNotesText(location: Int, length: Int) {
        pendingNotesTextReveal = PanelTextRevealRequest(
            location: max(0, location),
            length: max(0, length)
        )
    }

    func consumeNotesTextReveal() {
        pendingNotesTextReveal = nil
    }

    func consumeSceneReplaceRequest(_ requestID: UUID) {
        guard pendingSceneReplace?.requestID == requestID else { return }
        pendingSceneReplace = nil
    }

    func consumeSceneReplaceAllRequest(_ requestID: UUID) {
        guard pendingSceneReplaceAll?.requestID == requestID else { return }
        pendingSceneReplaceAll = nil
    }

    /// Called by EditorView after it performs an undo-aware replacement
    /// in the displayed scene's NSTextView.
    func didCompleteEditorReplace() {
        refreshGlobalSearchResults()
        _ = selectNextGlobalSearchResult()
        saveProject(debounced: false)
    }

    /// Called by EditorView after it performs an undo-aware replace-all
    /// in the displayed scene's NSTextView.
    func didCompleteEditorReplaceAll(count: Int) {
        if count > 0 {
            refreshGlobalSearchResults()
            saveProject(debounced: false)
        }
    }

    func searchScenes(
        _ query: String,
        caseSensitive: Bool = false,
        maxResults: Int = 300
    ) -> [SceneSearchResult] {
        guard isProjectOpen else { return [] }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        let compareOptions: NSString.CompareOptions = caseSensitive
            ? []
            : [.caseInsensitive, .diacriticInsensitive]

        var output: [SceneSearchResult] = []

        for chapter in project.chapters {
            let chapterTitle = displayChapterTitle(chapter)

            for scene in chapter.scenes {
                let sceneTitle = displaySceneTitle(scene)
                let sceneText = scene.content
                let sceneNSString = sceneText as NSString
                guard sceneNSString.length > 0 else { continue }

                var searchStart = 0
                while searchStart < sceneNSString.length {
                    let searchRange = NSRange(
                        location: searchStart,
                        length: sceneNSString.length - searchStart
                    )
                    let foundRange = sceneNSString.range(
                        of: normalizedQuery,
                        options: compareOptions,
                        range: searchRange
                    )
                    guard foundRange.location != NSNotFound else { break }

                    output.append(
                        SceneSearchResult(
                            chapterID: chapter.id,
                            sceneID: scene.id,
                            chapterTitle: chapterTitle,
                            sceneTitle: sceneTitle,
                            location: foundRange.location,
                            length: foundRange.length,
                            snippet: searchSnippet(
                                in: sceneNSString,
                                matchRange: foundRange
                            )
                        )
                    )

                    if output.count >= maxResults {
                        return output
                    }

                    searchStart = foundRange.location + max(foundRange.length, 1)
                }
            }
        }

        return output
    }

    var generationModelOptions: [String] {
        if !availableRemoteModels.isEmpty {
            return availableRemoteModels
        }

        var output: [String] = []
        var seen = Set<String>()

        let selected = normalizedModelSelection(project.settings.generationModelSelection)
        for model in selected where seen.insert(model).inserted {
            output.append(model)
        }

        let current = project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, seen.insert(current).inserted {
            output.append(current)
        }

        for model in availableRemoteModels where seen.insert(model).inserted {
            output.append(model)
        }

        return output
    }

    var selectedGenerationModels: [String] {
        if !availableRemoteModels.isEmpty {
            let discovered = Set(availableRemoteModels)
            let selected = normalizedModelSelection(project.settings.generationModelSelection)
                .filter { discovered.contains($0) }
            if !selected.isEmpty {
                return selected
            }

            let current = project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if discovered.contains(current) {
                return [current]
            }

            if let first = availableRemoteModels.first {
                return [first]
            }
            return []
        }

        let selected = normalizedModelSelection(project.settings.generationModelSelection)
        if !selected.isEmpty {
            return selected
        }

        let current = project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? [] : [current]
    }

    var selectedGenerationModelsLabel: String {
        let selected = selectedGenerationModels
        if selected.isEmpty {
            return "Select Models"
        }
        if selected.count == 1 {
            return selected[0]
        }
        return "\(selected.count) Models"
    }

    var useInlineGeneration: Bool {
        project.settings.useInlineGeneration
    }

    var markRewrittenTextAsItalics: Bool {
        project.settings.markRewrittenTextAsItalics
    }

    var incrementalRewrite: Bool {
        project.settings.incrementalRewrite
    }

    func isGenerationModelSelected(_ model: String) -> Bool {
        selectedGenerationModels.contains(model.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func entries(in category: CompendiumCategory) -> [CompendiumEntry] {
        project.compendium
            .filter { $0.category == category }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var selectedSceneContextCompendiumIDs: [UUID] {
        compendiumContextIDs(for: selectedSceneID)
    }

    var selectedSceneContextCompendiumEntries: [CompendiumEntry] {
        compendiumEntries(forIDs: selectedSceneContextCompendiumIDs)
    }

    var selectedSceneContextSceneSummaryIDs: [UUID] {
        sceneSummaryContextIDs(for: selectedSceneID)
    }

    var selectedSceneContextChapterSummaryIDs: [UUID] {
        chapterSummaryContextIDs(for: selectedSceneID)
    }

    var selectedSceneContextTotalCount: Int {
        selectedSceneContextCompendiumIDs.count
            + selectedSceneContextSceneSummaryIDs.count
            + selectedSceneContextChapterSummaryIDs.count
    }

    var selectedSceneNarrativeState: SceneNarrativeState {
        sceneNarrativeState(for: selectedSceneID)
    }

    // MARK: - Project Lifecycle

    func createNewProject(at destinationURL: URL) throws {
        try persistOpenProjectIfNeeded()

        let newProject = StoryProject.starter()
        let savedURL = try persistence.createProject(newProject, at: destinationURL)
        applyLoadedProject(newProject, from: savedURL, rememberAsLastOpened: true)
    }

    func openProject(at projectURL: URL) throws {
        try persistOpenProjectIfNeeded()

        let loadedProject = try persistence.loadProject(at: projectURL)
        let resolvedURL = try persistence.resolveExistingProjectURL(projectURL)
        applyLoadedProject(loadedProject, from: resolvedURL, rememberAsLastOpened: true)
    }

    func closeProject() {
        try? persistOpenProjectIfNeeded()
        setClosedProjectState(clearLastOpenedReference: true)
    }

    func duplicateCurrentProject(to destinationURL: URL) throws {
        guard let sourceURL = currentProjectURL, isProjectOpen else {
            throw ProjectPersistenceError.projectNotFound
        }

        try persistOpenProjectIfNeeded()
        let duplicatedURL = try persistence.duplicateProject(from: sourceURL, to: destinationURL)
        let duplicatedProject = try persistence.loadProject(at: duplicatedURL)
        applyLoadedProject(duplicatedProject, from: duplicatedURL, rememberAsLastOpened: true)
    }

    @discardableResult
    func createProjectCheckpointNow() throws -> ProjectCheckpointSummary {
        guard isProjectOpen, let currentProjectURL else {
            throw ProjectPersistenceError.projectNotFound
        }

        let checkpoint = try persistence.createCheckpoint(for: project, at: currentProjectURL)
        synchronizeDocumentModificationDateIfNeeded()
        refreshProjectCheckpoints()
        return ProjectCheckpointSummary(
            id: checkpoint.id,
            fileName: checkpoint.fileName,
            createdAt: checkpoint.createdAt
        )
    }

    func restoreProjectCheckpoint(
        checkpointID: String,
        options: CheckpointRestoreOptions
    ) throws {
        guard isProjectOpen, let currentProjectURL else {
            throw ProjectPersistenceError.projectNotFound
        }

        guard !options.isNoOp else { return }

        let checkpointProject = try persistence.loadCheckpoint(
            at: currentProjectURL,
            fileName: checkpointID
        )

        applyCheckpointRestore(checkpointProject, options: options)
    }

    func sceneCheckpointSnapshots(for sceneID: UUID) -> [SceneCheckpointSnapshot] {
        guard isProjectOpen, let currentProjectURL else {
            return []
        }

        var snapshots: [SceneCheckpointSnapshot] = []
        for checkpoint in projectCheckpoints {
            guard let checkpointProject = try? persistence.loadCheckpoint(
                at: currentProjectURL,
                fileName: checkpoint.fileName
            ) else {
                continue
            }

            guard let location = sceneLocation(for: sceneID, in: checkpointProject) else {
                continue
            }

            let scene = checkpointProject.chapters[location.chapterIndex].scenes[location.sceneIndex]
            snapshots.append(
                SceneCheckpointSnapshot(
                    id: checkpoint.id,
                    checkpointFileName: checkpoint.fileName,
                    checkpointCreatedAt: checkpoint.createdAt,
                    sceneContent: scene.content,
                    sceneContentRTFData: scene.contentRTFData
                )
            )
        }

        return snapshots
    }

    func restoreSceneTextFromCheckpoint(
        checkpointFileName: String,
        sceneID: UUID
    ) throws {
        guard isProjectOpen, let currentProjectURL else {
            throw ProjectPersistenceError.projectNotFound
        }

        let checkpointProject = try persistence.loadCheckpoint(
            at: currentProjectURL,
            fileName: checkpointFileName
        )

        guard let sourceLocation = sceneLocation(for: sceneID, in: checkpointProject) else {
            throw DataExchangeError.checkpointSceneNotFoundInCheckpoint
        }
        guard let destinationLocation = sceneLocation(for: sceneID) else {
            throw DataExchangeError.checkpointSceneNotFoundInProject
        }

        let sourceScene = checkpointProject.chapters[sourceLocation.chapterIndex].scenes[sourceLocation.sceneIndex]
        project.chapters[destinationLocation.chapterIndex].scenes[destinationLocation.sceneIndex].content = sourceScene.content
        project.chapters[destinationLocation.chapterIndex].scenes[destinationLocation.sceneIndex].contentRTFData = sourceScene.contentRTFData
        project.chapters[destinationLocation.chapterIndex].scenes[destinationLocation.sceneIndex].updatedAt = .now
        project.chapters[destinationLocation.chapterIndex].updatedAt = .now
        sceneRichTextRefreshID = UUID()
        saveProject(forceWrite: true)
    }

    func refreshProjectCheckpoints() {
        guard isProjectOpen, let currentProjectURL else {
            projectCheckpoints = []
            return
        }

        do {
            let checkpoints = try persistence.listCheckpoints(at: currentProjectURL)
            projectCheckpoints = checkpoints.map {
                ProjectCheckpointSummary(
                    id: $0.id,
                    fileName: $0.fileName,
                    createdAt: $0.createdAt
                )
            }
        } catch {
            projectCheckpoints = []
            lastError = "Failed to load checkpoints: \(error.localizedDescription)"
        }
    }

    // MARK: - Document Sync

    func bindToDocumentChanges(_ handler: @escaping (StoryProject) -> Void) {
        guard isDocumentBacked else { return }
        documentChangeHandler = handler
    }

    func synchronizeProjectToDocument() {
        guard isDocumentBacked else { return }
        documentChangeHandler?(project)
    }

    func updateProjectURL(_ projectURL: URL?) {
        let normalizedURL = projectURL?.standardizedFileURL
        currentProjectURL = normalizedURL
        refreshProjectCheckpoints()

        if isDocumentBacked, let normalizedURL {
            persistence.saveLastOpenedProjectURL(normalizedURL)
            NSDocumentController.shared.noteNewRecentDocumentURL(normalizedURL)
        }
    }

    func replaceProjectFromDocument(_ project: StoryProject) {
        guard isDocumentBacked else { return }
        autosaveTask?.cancel()

        self.project = project
        ensureProjectBaseline()
        selectedSceneID = self.project.selectedSceneID ?? self.project.chapters.first?.scenes.first?.id
        if let selectedSceneID,
           let location = sceneLocation(for: selectedSceneID) {
            selectedChapterID = self.project.chapters[location.chapterIndex].id
        } else {
            selectedChapterID = self.project.chapters.first?.id
        }
        ensureValidSelections()
        refreshGlobalSearchResults()

        if project.settings.provider.supportsModelDiscovery {
            scheduleModelDiscovery(immediate: true)
        } else {
            modelDiscoveryTask?.cancel()
            availableRemoteModels = []
            isDiscoveringModels = false
            modelDiscoveryStatus = ""
        }

        refreshProjectCheckpoints()
    }

    // MARK: - Selection

    func selectChapter(_ chapterID: UUID) {
        guard isProjectOpen else { return }
        selectedChapterID = chapterID
        let firstSceneID = project.chapters.first(where: { $0.id == chapterID })?.scenes.first?.id
        selectedSceneID = firstSceneID
        project.selectedSceneID = selectedSceneID
        saveProject(debounced: true)
    }

    func selectScene(_ sceneID: UUID, chapterID: UUID) {
        guard isProjectOpen else { return }
        selectedChapterID = chapterID
        selectedSceneID = sceneID
        project.selectedSceneID = sceneID
        saveProject(debounced: true)
    }

    func isCompendiumEntrySelectedForCurrentSceneContext(_ entryID: UUID) -> Bool {
        selectedSceneContextCompendiumIDs.contains(entryID)
    }

    func toggleCompendiumEntryForCurrentSceneContext(_ entryID: UUID) {
        guard selectedSceneID != nil else { return }
        setCompendiumContextIDsForCurrentScene(
            toggledContextSelectionID(entryID, in: selectedSceneContextCompendiumIDs)
        )
    }

    func clearCurrentSceneContextCompendiumSelection() {
        clearCurrentSceneContextSelection()
    }

    func clearCurrentSceneContextSelection() {
        setCompendiumContextIDsForCurrentScene([])
        setSceneSummaryContextIDsForCurrentScene([])
        setChapterSummaryContextIDsForCurrentScene([])
    }

    func setCompendiumContextIDsForCurrentScene(_ entryIDs: [UUID]) {
        guard let selectedSceneID else { return }
        setCompendiumContextIDs(entryIDs, for: selectedSceneID)
    }

    func isSceneSummarySelectedForCurrentSceneContext(_ sceneID: UUID) -> Bool {
        selectedSceneContextSceneSummaryIDs.contains(sceneID)
    }

    func toggleSceneSummaryForCurrentSceneContext(_ sceneID: UUID) {
        guard selectedSceneID != nil else { return }
        setSceneSummaryContextIDsForCurrentScene(
            toggledContextSelectionID(sceneID, in: selectedSceneContextSceneSummaryIDs)
        )
    }

    func setSceneSummaryContextIDsForCurrentScene(_ sceneIDs: [UUID]) {
        guard let selectedSceneID else { return }
        setSceneSummaryContextIDs(sceneIDs, for: selectedSceneID)
    }

    func isChapterSummarySelectedForCurrentSceneContext(_ chapterID: UUID) -> Bool {
        selectedSceneContextChapterSummaryIDs.contains(chapterID)
    }

    func toggleChapterSummaryForCurrentSceneContext(_ chapterID: UUID) {
        guard selectedSceneID != nil else { return }
        setChapterSummaryContextIDsForCurrentScene(
            toggledContextSelectionID(chapterID, in: selectedSceneContextChapterSummaryIDs)
        )
    }

    func setChapterSummaryContextIDsForCurrentScene(_ chapterIDs: [UUID]) {
        guard let selectedSceneID else { return }
        setChapterSummaryContextIDs(chapterIDs, for: selectedSceneID)
    }

    func updateSelectedSceneNarrativePOV(_ value: String?) {
        updateSelectedSceneNarrativeStateValue(\.pov, value: value)
    }

    func updateSelectedSceneNarrativeTense(_ value: String?) {
        updateSelectedSceneNarrativeStateValue(\.tense, value: value)
    }

    func updateSelectedSceneNarrativeLocation(_ value: String?) {
        updateSelectedSceneNarrativeStateValue(\.location, value: value)
    }

    func updateSelectedSceneNarrativeTime(_ value: String?) {
        updateSelectedSceneNarrativeStateValue(\.time, value: value)
    }

    func updateSelectedSceneNarrativeGoal(_ value: String?) {
        updateSelectedSceneNarrativeStateValue(\.goal, value: value)
    }

    func updateSelectedSceneNarrativeEmotion(_ value: String?) {
        updateSelectedSceneNarrativeStateValue(\.emotion, value: value)
    }

    func clearSelectedSceneNarrativeState() {
        guard let selectedSceneID else { return }
        project.sceneNarrativeStates.removeValue(forKey: selectedSceneID.uuidString)
        saveProject(debounced: true)
    }

    func selectCompendiumEntry(_ entryID: UUID?) {
        guard isProjectOpen else { return }
        selectedCompendiumID = entryID
    }

    func selectWorkshopSession(_ sessionID: UUID) {
        guard isProjectOpen else { return }
        guard workshopSessionIndex(for: sessionID) != nil else { return }
        selectedWorkshopSessionID = sessionID
        project.selectedWorkshopSessionID = sessionID
        syncWorkshopContextTogglesFromSelectedSession()
        saveProject(debounced: true)
    }

    func setWorkshopUseSceneContext(_ enabled: Bool) {
        guard workshopUseSceneContext != enabled else { return }
        workshopUseSceneContext = enabled
        persistWorkshopContextTogglesForSelectedSession()
    }

    func setWorkshopUseCompendiumContext(_ enabled: Bool) {
        guard workshopUseCompendiumContext != enabled else { return }
        workshopUseCompendiumContext = enabled
        persistWorkshopContextTogglesForSelectedSession()
    }

    // MARK: - Project and Settings

    func updateEditorAppearance(_ appearance: EditorAppearanceSettings) {
        guard project.editorAppearance != appearance else { return }
        project.editorAppearance = appearance
        saveProject(debounced: true)
    }

    func applyEditorAppearanceToExistingText() {
        guard isProjectOpen else { return }

        let appearance = project.editorAppearance
        let baseFont = resolvedEditorBaseFont(from: appearance)
        let textColor = resolvedEditorTextColor(from: appearance)
        let alignment = nsTextAlignment(from: appearance.textAlignment)
        let lineHeightMultiple = max(1.0, appearance.lineHeightMultiple)
        let paragraphIndent = max(0, appearance.paragraphIndent)

        var didMutateProject = false

        for chapterIndex in project.chapters.indices {
            var didMutateChapter = false

            for sceneIndex in project.chapters[chapterIndex].scenes.indices {
                let scene = project.chapters[chapterIndex].scenes[sceneIndex]
                let attributed = makeAttributedSceneContent(
                    plainText: scene.content,
                    richTextData: scene.contentRTFData
                )

                let fullRange = NSRange(location: 0, length: attributed.length)
                guard fullRange.length > 0 else { continue }

                attributed.beginEditing()
                attributed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                    let sourceFont = (value as? NSFont) ?? baseFont
                    let mappedFont = mapMarkdownFontTraits(sourceFont, onto: baseFont)
                    attributed.addAttribute(.font, value: mappedFont, range: range)
                }
                attributed.addAttribute(.foregroundColor, value: textColor, range: fullRange)
                attributed.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
                    let paragraphStyle = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                        ?? NSMutableParagraphStyle()
                    paragraphStyle.lineHeightMultiple = lineHeightMultiple
                    paragraphStyle.alignment = alignment
                    paragraphStyle.lineBreakMode = .byWordWrapping
                    paragraphStyle.firstLineHeadIndent = paragraphIndent
                    attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
                }
                attributed.endEditing()

                let updatedPlainText = attributed.string
                let updatedRichTextData = makeRTFData(from: attributed)
                if scene.content == updatedPlainText && scene.contentRTFData == updatedRichTextData {
                    continue
                }

                project.chapters[chapterIndex].scenes[sceneIndex].content = updatedPlainText
                project.chapters[chapterIndex].scenes[sceneIndex].contentRTFData = updatedRichTextData
                project.chapters[chapterIndex].scenes[sceneIndex].updatedAt = .now
                didMutateChapter = true
                didMutateProject = true
            }

            if didMutateChapter {
                project.chapters[chapterIndex].updatedAt = .now
            }
        }

        guard didMutateProject else { return }
        sceneRichTextRefreshID = UUID()
        saveProject()
    }

    func updateProjectTitle(_ title: String) {
        project.title = title
        saveProject(debounced: true)
    }

    func updateProjectAuthor(_ author: String) {
        updateProjectMetadataField(\.author, value: author)
    }

    func updateProjectLanguage(_ language: String) {
        updateProjectMetadataField(\.language, value: language)
    }

    func updateProjectPublisher(_ publisher: String) {
        updateProjectMetadataField(\.publisher, value: publisher)
    }

    func updateProjectRights(_ rights: String) {
        updateProjectMetadataField(\.rights, value: rights)
    }

    func updateProjectDescription(_ description: String) {
        updateProjectMetadataField(\.description, value: description)
    }

    private func updateProjectMetadataField(
        _ keyPath: WritableKeyPath<ProjectMetadata, String?>,
        value: String
    ) {
        let normalized = normalizedProjectMetadataValue(value)
        guard project.metadata[keyPath: keyPath] != normalized else { return }
        project.metadata[keyPath: keyPath] = normalized
        saveProject(debounced: true)
    }

    private func normalizedProjectMetadataValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func updateAutosaveEnabled(_ enabled: Bool) {
        guard project.autosaveEnabled != enabled else { return }
        project.autosaveEnabled = enabled
        saveProject(forceWrite: true)
    }

    func updateProvider(_ provider: AIProvider) {
        let previousProvider = project.settings.provider
        project.settings.provider = provider

        let endpoint = project.settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.isEmpty || endpoint == previousProvider.defaultEndpoint {
            project.settings.endpoint = provider.defaultEndpoint
        }

        if provider.supportsModelDiscovery {
            scheduleModelDiscovery(immediate: true)
        } else {
            modelDiscoveryTask?.cancel()
            availableRemoteModels = []
            isDiscoveringModels = false
            modelDiscoveryStatus = "Model discovery is unavailable for this provider."
        }
        saveProject(debounced: true)
    }

    func updateEndpoint(_ endpoint: String) {
        project.settings.endpoint = endpoint
        scheduleModelDiscovery()
        saveProject(debounced: true)
    }

    func updateAPIKey(_ apiKey: String) {
        project.settings.apiKey = apiKey
        scheduleModelDiscovery()
        saveProject(debounced: true)
    }

    func updateModel(_ model: String) {
        project.settings.model = model
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelection = normalizedModelSelection(project.settings.generationModelSelection)
        if normalizedSelection.isEmpty {
            project.settings.generationModelSelection = trimmed.isEmpty ? [] : [trimmed]
        } else if normalizedSelection.count == 1, !trimmed.isEmpty, normalizedSelection[0] != trimmed {
            project.settings.generationModelSelection = [trimmed]
        }
        saveProject(debounced: true)
    }

    func toggleGenerationModelSelection(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !availableRemoteModels.isEmpty, !availableRemoteModels.contains(trimmed) {
            return
        }

        var selected = normalizedModelSelection(project.settings.generationModelSelection)
        if let index = selected.firstIndex(of: trimmed) {
            selected.remove(at: index)
        } else {
            selected.append(trimmed)
        }

        if selected.isEmpty {
            let fallback = project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                selected = [fallback]
            }
        }

        project.settings.generationModelSelection = selected
        saveProject(debounced: true)
    }

    func selectOnlyGenerationModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !availableRemoteModels.isEmpty, !availableRemoteModels.contains(trimmed) {
            return
        }

        project.settings.generationModelSelection = [trimmed]
        saveProject(debounced: true)
    }

    func updateUseInlineGeneration(_ enabled: Bool) {
        guard project.settings.useInlineGeneration != enabled else { return }
        project.settings.useInlineGeneration = enabled
        saveProject(debounced: true)
    }

    func updateMarkRewrittenTextAsItalics(_ enabled: Bool) {
        guard project.settings.markRewrittenTextAsItalics != enabled else { return }
        project.settings.markRewrittenTextAsItalics = enabled
        saveProject(debounced: true)
    }

    func updateIncrementalRewrite(_ enabled: Bool) {
        guard project.settings.incrementalRewrite != enabled else { return }
        project.settings.incrementalRewrite = enabled
        saveProject(debounced: true)
    }

    func updatePreferCompactPromptTemplates(_ enabled: Bool) {
        guard project.settings.preferCompactPromptTemplates != enabled else { return }
        project.settings.preferCompactPromptTemplates = enabled
        saveProject(debounced: true)
    }

    func updateTemperature(_ temperature: Double) {
        project.settings.temperature = temperature
        saveProject(debounced: true)
    }

    func updateMaxTokens(_ maxTokens: Int) {
        project.settings.maxTokens = maxTokens
        saveProject(debounced: true)
    }

    func updateEnableStreaming(_ enabled: Bool) {
        project.settings.enableStreaming = enabled
        saveProject(debounced: true)
    }

    func updateRequestTimeoutSeconds(_ timeout: Double) {
        project.settings.requestTimeoutSeconds = min(max(timeout, 1), 3600)
        saveProject(debounced: true)
    }

    func updateEnableTaskNotifications(_ enabled: Bool) {
        guard project.settings.enableTaskNotifications != enabled else { return }
        project.settings.enableTaskNotifications = enabled
        if !enabled {
            clearTaskNotificationToasts()
        }
        saveProject(debounced: true)
    }

    func updateShowTaskProgressNotifications(_ enabled: Bool) {
        guard project.settings.showTaskProgressNotifications != enabled else { return }
        project.settings.showTaskProgressNotifications = enabled
        saveProject(debounced: true)
    }

    func updateShowTaskCancellationNotifications(_ enabled: Bool) {
        guard project.settings.showTaskCancellationNotifications != enabled else { return }
        project.settings.showTaskCancellationNotifications = enabled
        saveProject(debounced: true)
    }

    func updateTaskNotificationDurationSeconds(_ seconds: Double) {
        let normalized = min(max(seconds, 1), 30)
        guard abs(project.settings.taskNotificationDurationSeconds - normalized) > 0.001 else { return }
        project.settings.taskNotificationDurationSeconds = normalized
        saveProject(debounced: true)
    }

    func dismissTaskNotificationToast(_ id: UUID) {
        cancelTaskToastDismiss(id)
        taskNotificationToasts.removeAll { $0.id == id }
    }

    private var taskNotificationDuration: TimeInterval {
        min(max(project.settings.taskNotificationDurationSeconds, 1), 30)
    }

    private func clearTaskNotificationToasts() {
        for task in toastDismissTasks.values {
            task.cancel()
        }
        toastDismissTasks.removeAll()
        taskNotificationToasts = []
    }

    private func cancelTaskToastDismiss(_ id: UUID) {
        toastDismissTasks[id]?.cancel()
        toastDismissTasks.removeValue(forKey: id)
    }

    private func scheduleTaskToastDismiss(_ id: UUID, after seconds: TimeInterval) {
        cancelTaskToastDismiss(id)
        toastDismissTasks[id] = Task { [weak self] in
            let delay = UInt64(max(0.2, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.dismissTaskNotificationToast(id)
            }
        }
    }

    @discardableResult
    private func showTaskNotification(
        _ message: String,
        style: TaskNotificationToast.Style,
        updating toastID: UUID? = nil,
        autoDismiss: Bool
    ) -> UUID? {
        guard project.settings.enableTaskNotifications else {
            if let toastID {
                dismissTaskNotificationToast(toastID)
            }
            return nil
        }

        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return toastID }

        let id = toastID ?? UUID()
        let now = Date()
        if let index = taskNotificationToasts.firstIndex(where: { $0.id == id }) {
            taskNotificationToasts[index].message = normalized
            taskNotificationToasts[index].style = style
            taskNotificationToasts[index].createdAt = now
        } else {
            taskNotificationToasts.append(
                TaskNotificationToast(
                    id: id,
                    message: normalized,
                    style: style,
                    createdAt: now
                )
            )
        }

        if taskNotificationToasts.count > Self.maxVisibleTaskToasts {
            let overflow = taskNotificationToasts.count - Self.maxVisibleTaskToasts
            let removed = taskNotificationToasts.prefix(overflow)
            for toast in removed {
                cancelTaskToastDismiss(toast.id)
            }
            taskNotificationToasts.removeFirst(overflow)
        }

        if autoDismiss {
            scheduleTaskToastDismiss(id, after: taskNotificationDuration)
        } else {
            cancelTaskToastDismiss(id)
        }

        return id
    }

    @discardableResult
    private func startTaskProgressToast(_ message: String) -> UUID? {
        guard project.settings.showTaskProgressNotifications else { return nil }
        return showTaskNotification(
            message,
            style: .progress,
            updating: nil,
            autoDismiss: false
        )
    }

    private func finishTaskSuccessToast(_ toastID: UUID?, _ message: String) {
        _ = showTaskNotification(
            message,
            style: .success,
            updating: toastID,
            autoDismiss: true
        )
    }

    private func finishTaskErrorToast(_ toastID: UUID?, _ message: String) {
        _ = showTaskNotification(
            message,
            style: .error,
            updating: toastID,
            autoDismiss: true
        )
    }

    private func finishTaskWarningToast(_ toastID: UUID?, _ message: String) {
        _ = showTaskNotification(
            message,
            style: .warning,
            updating: toastID,
            autoDismiss: true
        )
    }

    private func finishTaskCancelledToast(_ toastID: UUID?, _ message: String) {
        guard project.settings.showTaskCancellationNotifications else {
            if let toastID {
                dismissTaskNotificationToast(toastID)
            }
            return
        }
        _ = showTaskNotification(
            message,
            style: .cancelled,
            updating: toastID,
            autoDismiss: true
        )
    }

    func updateDefaultSystemPrompt(_ prompt: String) {
        project.settings.defaultSystemPrompt = prompt
        saveProject(debounced: true)
    }

    func refreshAvailableModels(force: Bool = false, showErrors: Bool = true) async {
        guard isProjectOpen else {
            availableRemoteModels = []
            modelDiscoveryStatus = ""
            isDiscoveringModels = false
            return
        }

        guard project.settings.provider.supportsModelDiscovery else {
            availableRemoteModels = []
            modelDiscoveryStatus = "Model discovery is unavailable for this provider."
            return
        }

        let endpoint = project.settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            availableRemoteModels = []
            modelDiscoveryStatus = "Set endpoint URL to discover available models."
            return
        }

        if isDiscoveringModels && !force {
            return
        }

        isDiscoveringModels = true
        modelDiscoveryStatus = "Discovering models..."

        defer {
            isDiscoveringModels = false
        }

        do {
            let discovered: [String]
            if project.settings.provider == .anthropic {
                discovered = try await anthropicService.fetchAvailableModels(settings: project.settings)
            } else {
                discovered = try await openAIService.fetchAvailableModels(settings: project.settings)
            }
            let normalizedDiscovered = normalizedModelSelection(discovered)
            availableRemoteModels = normalizedDiscovered

            if normalizedDiscovered.isEmpty {
                modelDiscoveryStatus = "No models returned by endpoint."
                return
            }

            modelDiscoveryStatus = "Discovered \(normalizedDiscovered.count) model(s)."
            if reconcileGenerationModels(withDiscovered: normalizedDiscovered) {
                saveProject(debounced: true)
            }
        } catch AIServiceError.invalidEndpoint {
            availableRemoteModels = []
            modelDiscoveryStatus = "Endpoint URL is invalid."
        } catch {
            availableRemoteModels = []
            modelDiscoveryStatus = "Model discovery failed."
            if showErrors {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Data Exchange

    @discardableResult
    func exportPrompts(to fileURL: URL) throws -> Int {
        guard isProjectOpen else {
            throw DataExchangeError.projectNotOpen
        }

        let latestBuiltIns = PromptTemplate.latestBuiltInTemplates(
            preferCompact: project.settings.preferCompactPromptTemplates
        )
        let builtInByID = Dictionary(uniqueKeysWithValues: latestBuiltIns.map { ($0.id, $0) })
        let exportablePrompts: [PromptTransferRecord] = project.prompts.compactMap { prompt in
            if let builtIn = builtInByID[prompt.id],
               !isBuiltInPromptModified(prompt, comparedTo: builtIn) {
                return nil
            }

            return PromptTransferRecord(
                templateID: prompt.id,
                category: prompt.category.rawValue,
                title: prompt.title,
                userTemplate: prompt.userTemplate,
                systemTemplate: prompt.systemTemplate
            )
        }

        let envelope = PromptTransferEnvelope(
            version: Self.transferVersion,
            type: Self.promptTransferType,
            exportedAt: .now,
            prompts: exportablePrompts
        )

        let data = try Self.transferEncoder.encode(envelope)
        try data.write(to: fileURL, options: Data.WritingOptions.atomic)
        return exportablePrompts.count
    }

    @discardableResult
    func importPrompts(from fileURL: URL) throws -> PromptImportReport {
        guard isProjectOpen else {
            throw DataExchangeError.projectNotOpen
        }

        let data = try Data(contentsOf: fileURL)
        let envelope = try Self.transferDecoder.decode(PromptTransferEnvelope.self, from: data)
        guard envelope.type == Self.promptTransferType else {
            throw DataExchangeError.invalidPayloadType(
                expected: Self.promptTransferType,
                actual: envelope.type
            )
        }

        var usedTitlesByCategory: [PromptCategory: Set<String>] = [:]
        for category in PromptCategory.allCases {
            let titles = project.prompts
                .filter { $0.category == category }
                .map { normalizedPromptTitle($0.title) }
            usedTitlesByCategory[category] = Set(titles)
        }

        var importedCount = 0
        var skippedCount = 0

        for record in envelope.prompts {
            guard let category = PromptCategory(rawValue: record.category) else {
                skippedCount += 1
                continue
            }

            if let templateID = record.templateID,
               Self.builtInPromptIDs.contains(templateID),
               let index = promptIndex(for: templateID) {
                let normalizedTitle = normalizedPromptTitle(project.prompts[index].title)
                usedTitlesByCategory[project.prompts[index].category]?.remove(normalizedTitle)
                project.prompts[index].title = record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? project.prompts[index].title
                    : record.title
                project.prompts[index].userTemplate = record.userTemplate
                project.prompts[index].systemTemplate = record.systemTemplate
                usedTitlesByCategory[project.prompts[index].category, default: []]
                    .insert(normalizedPromptTitle(project.prompts[index].title))
                importedCount += 1
                continue
            }

            let title = makeUniqueImportedTitle(
                baseTitle: record.title,
                fallback: promptTitleBase(for: category),
                usedTitles: &usedTitlesByCategory[category, default: []]
            )

            let prompt = PromptTemplate(
                id: UUID(),
                category: category,
                title: title,
                userTemplate: record.userTemplate,
                systemTemplate: record.systemTemplate
            )

            project.prompts.append(prompt)
            importedCount += 1
        }

        ensureProjectBaseline()
        ensureValidSelections()
        saveProject(forceWrite: true)

        return PromptImportReport(importedCount: importedCount, skippedCount: skippedCount)
    }

    @discardableResult
    func exportCompendium(to fileURL: URL) throws -> Int {
        guard isProjectOpen else {
            throw DataExchangeError.projectNotOpen
        }

        let entries = project.compendium.map { entry in
            CompendiumTransferRecord(
                category: entry.category.rawValue,
                title: entry.title,
                body: entry.body,
                tags: entry.tags
            )
        }

        let envelope = CompendiumTransferEnvelope(
            version: Self.transferVersion,
            type: Self.compendiumTransferType,
            exportedAt: .now,
            entries: entries
        )

        let data = try Self.transferEncoder.encode(envelope)
        try data.write(to: fileURL, options: .atomic)
        return entries.count
    }

    @discardableResult
    func importCompendium(from fileURL: URL) throws -> CompendiumImportReport {
        guard isProjectOpen else {
            throw DataExchangeError.projectNotOpen
        }

        let data = try Data(contentsOf: fileURL)
        let envelope = try Self.transferDecoder.decode(CompendiumTransferEnvelope.self, from: data)
        guard envelope.type == Self.compendiumTransferType else {
            throw DataExchangeError.invalidPayloadType(
                expected: Self.compendiumTransferType,
                actual: envelope.type
            )
        }

        var usedTitlesByCategory: [CompendiumCategory: Set<String>] = [:]
        for category in CompendiumCategory.allCases {
            let titles = project.compendium
                .filter { $0.category == category }
                .map { normalizedEntryTitle($0.title) }
            usedTitlesByCategory[category] = Set(titles)
        }

        var importedCount = 0
        var skippedCount = 0

        for record in envelope.entries {
            guard let category = CompendiumCategory(rawValue: record.category) else {
                skippedCount += 1
                continue
            }

            let title = makeUniqueImportedTitle(
                baseTitle: record.title,
                fallback: "Imported Entry",
                usedTitles: &usedTitlesByCategory[category, default: []]
            )

            let tags = sanitizeImportedTags(record.tags)
            let entry = CompendiumEntry(
                id: UUID(),
                category: category,
                title: title,
                body: record.body,
                tags: tags,
                updatedAt: .now
            )

            project.compendium.append(entry)
            importedCount += 1
        }

        ensureValidSelections()
        saveProject(forceWrite: true)

        return CompendiumImportReport(importedCount: importedCount, skippedCount: skippedCount)
    }

    func exportProjectExchange(to fileURL: URL) throws {
        guard isProjectOpen else {
            throw DataExchangeError.projectNotOpen
        }

        let envelope = ProjectTransferEnvelope(
            version: Self.transferVersion,
            type: Self.projectTransferType,
            exportedAt: .now,
            project: project
        )

        let data = try Self.transferEncoder.encode(envelope)
        try data.write(to: fileURL, options: .atomic)
    }

    func importProjectExchange(from fileURL: URL) throws {
        let importedProject = try importedProjectFromExchange(fileURL: fileURL)
        applyImportedProject(importedProject)
    }

    func createProjectFromImportedExchange(from fileURL: URL, at destinationURL: URL) throws -> URL {
        let importedProject = try importedProjectFromExchange(fileURL: fileURL)
        return try createImportedProject(importedProject, at: destinationURL)
    }

    func exportProjectAsPlainText(to fileURL: URL) throws {
        guard isProjectOpen else {
            throw DataExchangeError.projectNotOpen
        }

        let text = makeProjectPlainTextExport()
        let data = Data(text.utf8)
        try data.write(to: fileURL, options: .atomic)
    }

    func exportProjectAsHTML(to fileURL: URL) throws {
        guard isProjectOpen else {
            throw DataExchangeError.projectNotOpen
        }

        let html = makeProjectHTMLExport()
        let data = Data(html.utf8)
        try data.write(to: fileURL, options: .atomic)
    }

    func exportProjectAsEPUB(to fileURL: URL) throws {
        guard isProjectOpen else {
            throw DataExchangeError.projectNotOpen
        }

        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("Scene-EPUB-\(UUID().uuidString)", isDirectory: true)
        let packageRoot = tempRoot.appendingPathComponent("package", isDirectory: true)
        let metaInfURL = packageRoot.appendingPathComponent("META-INF", isDirectory: true)
        let oebpsURL = packageRoot.appendingPathComponent("OEBPS", isDirectory: true)

        try fileManager.createDirectory(at: metaInfURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: oebpsURL, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        let mimetypeURL = packageRoot.appendingPathComponent("mimetype")
        try Data("application/epub+zip".utf8).write(to: mimetypeURL, options: .atomic)

        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try writeUTF8(containerXML, to: metaInfURL.appendingPathComponent("container.xml"))

        var chapterItems: [(id: String, href: String, title: String)] = []
        for (chapterIndex, chapter) in project.chapters.enumerated() {
            let itemID = "chapter-\(chapterIndex + 1)"
            let href = String(format: "chapter-%03d.xhtml", chapterIndex + 1)
            let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Chapter \(chapterIndex + 1)"
                : chapter.title

            let chapterXHTML = makeEPUBChapterXHTML(
                chapter: chapter,
                chapterTitle: chapterTitle,
                chapterIndex: chapterIndex
            )
            try writeUTF8(chapterXHTML, to: oebpsURL.appendingPathComponent(href))
            chapterItems.append((id: itemID, href: href, title: chapterTitle))
        }

        if chapterItems.isEmpty {
            let emptyChapter = Chapter(title: "Chapter 1", scenes: [Scene(title: "Scene 1", content: "")])
            let chapterXHTML = makeEPUBChapterXHTML(
                chapter: emptyChapter,
                chapterTitle: "Chapter 1",
                chapterIndex: 0
            )
            try writeUTF8(chapterXHTML, to: oebpsURL.appendingPathComponent("chapter-001.xhtml"))
            chapterItems.append((id: "chapter-1", href: "chapter-001.xhtml", title: "Chapter 1"))
        }

        let navXHTML = makeEPUBNavigationXHTML(chapters: chapterItems)
        try writeUTF8(navXHTML, to: oebpsURL.appendingPathComponent("nav.xhtml"))

        let projectEnvelope = ProjectTransferEnvelope(
            version: Self.transferVersion,
            type: Self.projectTransferType,
            exportedAt: .now,
            project: project
        )
        let projectEnvelopeData = try Self.transferEncoder.encode(projectEnvelope)
        try projectEnvelopeData.write(to: oebpsURL.appendingPathComponent("scene-project.json"), options: .atomic)

        let packageOPF = makeEPUBPackageOPF(chapters: chapterItems)
        try writeUTF8(packageOPF, to: oebpsURL.appendingPathComponent("content.opf"))

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        try createEPUBArchive(from: packageRoot, to: fileURL)
    }

    func importProjectFromEPUB(from fileURL: URL) throws {
        let importedProject = try importedProjectFromEPUB(fileURL: fileURL, fallbackProject: project)
        applyImportedProject(importedProject)
    }

    func createProjectFromImportedEPUB(from fileURL: URL, at destinationURL: URL) throws -> URL {
        let importedProject = try importedProjectFromEPUB(fileURL: fileURL, fallbackProject: StoryProject.starter())
        return try createImportedProject(importedProject, at: destinationURL)
    }

    private func importedProjectFromExchange(fileURL: URL) throws -> StoryProject {
        let data = try Data(contentsOf: fileURL)
        let envelope = try Self.transferDecoder.decode(ProjectTransferEnvelope.self, from: data)
        guard envelope.type == Self.projectTransferType else {
            throw DataExchangeError.invalidPayloadType(
                expected: Self.projectTransferType,
                actual: envelope.type
            )
        }
        return envelope.project
    }

    private func importedProjectFromEPUB(fileURL: URL, fallbackProject: StoryProject) throws -> StoryProject {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("Scene-EPUB-Import-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        do {
            try extractEPUBArchive(from: fileURL, to: tempRoot)
        } catch {
            throw DataExchangeError.invalidEPUB("Failed to unzip file.")
        }

        let packageRoot = try locateEPUBRoot(in: tempRoot)
        let descriptor = try parseEPUBPackageDescriptor(in: packageRoot)

        if let embeddedProject = try loadEmbeddedProjectFromEPUB(descriptor: descriptor) {
            return embeddedProject
        }

        let chapters = try parseEPUBChapters(descriptor: descriptor)
        guard !chapters.isEmpty else {
            throw DataExchangeError.invalidEPUB("No readable chapter content found.")
        }

        var importedProject = fallbackProject
        importedProject.title = descriptor.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Imported EPUB"
            : descriptor.title
        importedProject.metadata = descriptor.metadata
        importedProject.chapters = chapters
        importedProject.sceneContextCompendiumSelection = [:]
        importedProject.sceneContextSceneSummarySelection = [:]
        importedProject.sceneContextChapterSummarySelection = [:]
        importedProject.sceneNarrativeStates = [:]
        importedProject.workshopInputHistoryBySession = [:]
        importedProject.beatInputHistoryByScene = [:]
        importedProject.rollingWorkshopMemoryBySession = [:]
        importedProject.rollingSceneMemoryByScene = [:]
        importedProject.rollingChapterMemoryByChapter = [:]
        importedProject.selectedSceneID = chapters.first?.scenes.first?.id
        importedProject.updatedAt = .now

        return importedProject
    }

    private func createImportedProject(_ project: StoryProject, at destinationURL: URL) throws -> URL {
        let normalizedURL = persistence.normalizeProjectURL(destinationURL)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: normalizedURL.path) {
            try fileManager.removeItem(at: normalizedURL)
        }
        return try persistence.createProject(project, at: normalizedURL)
    }

    private func applyImportedProject(_ importedProject: StoryProject) {
        cancelProjectTasksForSwitch()

        project = importedProject
        isProjectOpen = true
        workshopInput = ""
        beatInput = ""
        generationStatus = ""
        workshopStatus = ""
        isGenerating = false
        workshopIsGenerating = false
        proseLiveUsage = nil
        proseGenerationReview = nil
        proseGenerationSessionContext = nil
        workshopLiveUsage = nil
        availableRemoteModels = []
        isDiscoveringModels = false
        modelDiscoveryStatus = ""
        resetGlobalSearchState()

        ensureProjectBaseline()
        selectedSceneID = project.selectedSceneID ?? project.chapters.first?.scenes.first?.id
        if let selectedSceneID,
           let location = sceneLocation(for: selectedSceneID) {
            selectedChapterID = project.chapters[location.chapterIndex].id
        } else {
            selectedChapterID = project.chapters.first?.id
        }
        ensureValidSelections()

        if project.settings.provider.supportsModelDiscovery {
            scheduleModelDiscovery(immediate: true)
        }

        saveProject(forceWrite: true)
    }

    // MARK: - Chapter / Scene

    func addChapter() {
        let chapterNumber = project.chapters.count + 1
        let starterScene = Scene(title: "Scene 1")
        let chapter = Chapter(title: "Chapter \(chapterNumber)", scenes: [starterScene])

        project.chapters.append(chapter)
        selectedChapterID = chapter.id
        selectedSceneID = starterScene.id
        project.selectedSceneID = starterScene.id
        saveProject()
    }

    func deleteChapter(_ chapterID: UUID) {
        let removedSceneIDs = Set(
            project.chapters
                .first(where: { $0.id == chapterID })?
                .scenes
                .map(\.id) ?? []
        )

        project.chapters.removeAll { $0.id == chapterID }
        project.rollingChapterMemoryByChapter.removeValue(forKey: chapterID.uuidString)
        removeChapterSummaryFromSceneContextSelections(chapterID)
        for sceneID in removedSceneIDs {
            removeSceneSummaryFromSceneContextSelections(sceneID)
            removeSceneContextSelection(for: sceneID)
        }

        if project.chapters.isEmpty {
            let replacement = Chapter(title: "Chapter 1", scenes: [Scene(title: "Scene 1")])
            project.chapters = [replacement]
        }

        ensureValidSelections()
        saveProject()
    }

    func canMoveChapterUp(_ chapterID: UUID) -> Bool {
        guard let index = project.chapters.firstIndex(where: { $0.id == chapterID }) else {
            return false
        }
        return index > 0
    }

    func canMoveChapterDown(_ chapterID: UUID) -> Bool {
        guard let index = project.chapters.firstIndex(where: { $0.id == chapterID }) else {
            return false
        }
        return index < project.chapters.count - 1
    }

    func moveChapterUp(_ chapterID: UUID) {
        guard let index = project.chapters.firstIndex(where: { $0.id == chapterID }),
              index > 0 else {
            return
        }

        project.chapters.swapAt(index, index - 1)
        saveProject()
    }

    func moveChapterDown(_ chapterID: UUID) {
        guard let index = project.chapters.firstIndex(where: { $0.id == chapterID }),
              index < project.chapters.count - 1 else {
            return
        }

        project.chapters.swapAt(index, index + 1)
        saveProject()
    }

    func addScene(to chapterID: UUID?) {
        let targetChapterID = chapterID ?? selectedChapterID ?? project.chapters.first?.id
        guard let targetChapterID,
              let chapterIndex = project.chapters.firstIndex(where: { $0.id == targetChapterID }) else {
            return
        }

        let sceneNumber = project.chapters[chapterIndex].scenes.count + 1
        let scene = Scene(title: "Scene \(sceneNumber)")

        project.chapters[chapterIndex].scenes.append(scene)
        project.chapters[chapterIndex].updatedAt = .now
        project.rollingChapterMemoryByChapter.removeValue(forKey: targetChapterID.uuidString)

        selectedChapterID = project.chapters[chapterIndex].id
        selectedSceneID = scene.id
        project.selectedSceneID = scene.id

        saveProject()
    }

    func deleteScene(_ sceneID: UUID) {
        let affectedChapterIDs = Set(
            project.chapters
                .filter { chapter in chapter.scenes.contains(where: { $0.id == sceneID }) }
                .map(\.id)
        )
        for chapterIndex in project.chapters.indices {
            project.chapters[chapterIndex].scenes.removeAll { $0.id == sceneID }
        }
        for chapterID in affectedChapterIDs {
            project.rollingChapterMemoryByChapter.removeValue(forKey: chapterID.uuidString)
        }
        removeSceneSummaryFromSceneContextSelections(sceneID)
        removeSceneContextSelection(for: sceneID)

        if !project.chapters.contains(where: { !$0.scenes.isEmpty }) {
            if project.chapters.isEmpty {
                project.chapters = [Chapter(title: "Chapter 1")]
            }
            project.chapters[0].scenes.append(Scene(title: "Scene 1"))
        }

        ensureValidSelections()
        saveProject()
    }

    func canMoveSceneUp(_ sceneID: UUID) -> Bool {
        guard let location = sceneLocation(for: sceneID) else { return false }
        return location.sceneIndex > 0
    }

    func canMoveSceneDown(_ sceneID: UUID) -> Bool {
        guard let location = sceneLocation(for: sceneID) else { return false }
        return location.sceneIndex < project.chapters[location.chapterIndex].scenes.count - 1
    }

    func moveSceneUp(_ sceneID: UUID) {
        guard let location = sceneLocation(for: sceneID),
              location.sceneIndex > 0 else {
            return
        }

        let chapterID = project.chapters[location.chapterIndex].id
        project.chapters[location.chapterIndex].scenes.swapAt(location.sceneIndex, location.sceneIndex - 1)
        project.chapters[location.chapterIndex].updatedAt = .now
        project.rollingChapterMemoryByChapter.removeValue(forKey: chapterID.uuidString)
        saveProject()
    }

    func moveSceneDown(_ sceneID: UUID) {
        guard let location = sceneLocation(for: sceneID),
              location.sceneIndex < project.chapters[location.chapterIndex].scenes.count - 1 else {
            return
        }

        let chapterID = project.chapters[location.chapterIndex].id
        project.chapters[location.chapterIndex].scenes.swapAt(location.sceneIndex, location.sceneIndex + 1)
        project.chapters[location.chapterIndex].updatedAt = .now
        project.rollingChapterMemoryByChapter.removeValue(forKey: chapterID.uuidString)
        saveProject()
    }

    func updateSelectedSceneTitle(_ title: String) {
        guard let selectedSceneID,
              let location = sceneLocation(for: selectedSceneID) else {
            return
        }

        project.chapters[location.chapterIndex].scenes[location.sceneIndex].title = title
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].updatedAt = .now
        project.chapters[location.chapterIndex].updatedAt = .now
        saveProject(debounced: true)
    }

    func renameChapter(_ chapterID: UUID, to title: String) {
        guard let index = chapterIndex(for: chapterID) else { return }
        project.chapters[index].title = title
        project.chapters[index].updatedAt = .now
        saveProject(debounced: true)
    }

    func renameScene(_ sceneID: UUID, to title: String) {
        guard let location = sceneLocation(for: sceneID) else { return }
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].title = title
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].updatedAt = .now
        project.chapters[location.chapterIndex].updatedAt = .now
        saveProject(debounced: true)
    }

    func moveScene(_ sceneID: UUID, toChapterID: UUID, atIndex: Int) {
        guard let sourceLocation = sceneLocation(for: sceneID),
              let targetChapterIndex = chapterIndex(for: toChapterID) else { return }

        let sourceChapterID = project.chapters[sourceLocation.chapterIndex].id
        let scene = project.chapters[sourceLocation.chapterIndex].scenes.remove(at: sourceLocation.sceneIndex)
        project.chapters[sourceLocation.chapterIndex].updatedAt = .now

        let clampedIndex = min(max(atIndex, 0), project.chapters[targetChapterIndex].scenes.count)
        project.chapters[targetChapterIndex].scenes.insert(scene, at: clampedIndex)
        project.chapters[targetChapterIndex].updatedAt = .now
        project.rollingChapterMemoryByChapter.removeValue(forKey: sourceChapterID.uuidString)
        project.rollingChapterMemoryByChapter.removeValue(forKey: toChapterID.uuidString)

        if selectedSceneID == sceneID {
            selectedChapterID = toChapterID
        }
        saveProject()
    }

    func moveChapter(_ chapterID: UUID, toIndex: Int) {
        guard let sourceIndex = chapterIndex(for: chapterID) else { return }
        let clampedIndex = min(max(toIndex, 0), project.chapters.count - 1)
        guard clampedIndex != sourceIndex else { return }

        let chapter = project.chapters.remove(at: sourceIndex)
        project.chapters.insert(chapter, at: clampedIndex)
        saveProject()
    }

    func updateSelectedSceneContent(_ content: String) {
        updateSelectedSceneContent(content, richTextData: nil)
    }

    func updateSelectedSceneContent(_ content: String, richTextData: Data?) {
        guard let selectedSceneID,
              let location = sceneLocation(for: selectedSceneID) else {
            return
        }

        project.chapters[location.chapterIndex].scenes[location.sceneIndex].content = content
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].contentRTFData = richTextData
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].updatedAt = .now
        project.chapters[location.chapterIndex].updatedAt = .now
        project.rollingSceneMemoryByScene.removeValue(forKey: selectedSceneID.uuidString)
        project.rollingChapterMemoryByChapter.removeValue(
            forKey: project.chapters[location.chapterIndex].id.uuidString
        )
        saveProject(debounced: true)
    }

    func updateSelectedSceneSummary(_ summary: String) {
        guard let selectedSceneID else {
            return
        }
        updateSceneSummary(sceneID: selectedSceneID, summary: summary, debounced: true)
    }

    func updateSelectedSceneRollingMemory(_ summary: String) {
        guard let selectedSceneID,
              let scene = selectedScene else {
            return
        }
        updateRollingSceneMemory(
            sceneID: selectedSceneID,
            summary: summary,
            sourceContent: scene.content
        )
        saveProject(debounced: true)
    }

    func refreshSelectedSceneRollingMemory(from sourceText: String) async throws -> String {
        guard let scene = selectedScene else {
            throw AIServiceError.badResponse("Select a scene first.")
        }

        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            throw AIServiceError.badResponse("Source text is empty.")
        }

        let sourceExcerpt = String(trimmedSource.prefix(Self.rollingSceneMemorySourceChars))
        let sceneID = scene.id
        let sceneTitle = displaySceneTitle(scene)
        let chapterTitleText = chapterTitle(forSceneID: sceneID)
        let existingMemory = project.rollingSceneMemoryByScene[sceneID.uuidString]?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let systemPrompt = """
        You maintain concise long-lived memory for a single fiction scene.

        Output rules:
        - Return plain prose bullets or short paragraphs only.
        - Keep stable facts, decisions, constraints, unresolved questions, and character intentions.
        - Remove repetition and low-value narration details.
        - Do not invent facts not present in input.
        """

        let userPrompt = """
        CHAPTER: \(chapterTitleText)
        SCENE: \(sceneTitle)

        EXISTING_MEMORY:
        <<<
        \(existingMemory)
        >>>

        SOURCE_TEXT:
        <<<
        \(sourceExcerpt)
        >>>

        TASK:
        Update the scene memory by merging EXISTING_MEMORY with SOURCE_TEXT. Keep the result compact and high-signal.
        """

        let request = TextGenerationRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: resolvedPrimaryModel(),
            temperature: min(project.settings.temperature, 0.3),
            maxTokens: min(project.settings.maxTokens, 900)
        )
        let toastID = startTaskProgressToast("Updating scene memory…")

        do {
            let result = try await generateTextResult(request)
            let normalizedSummary = normalizedRollingMemorySummary(
                result.text,
                maxChars: Self.rollingSceneMemoryMaxChars
            )
            guard !normalizedSummary.isEmpty else {
                throw AIServiceError.badResponse("Scene memory update was empty.")
            }

            updateRollingSceneMemory(
                sceneID: sceneID,
                summary: normalizedSummary,
                sourceContent: scene.content
            )
            saveProject(debounced: true)
            finishTaskSuccessToast(toastID, "Scene memory updated.")
            return normalizedSummary
        } catch is CancellationError {
            finishTaskCancelledToast(toastID, "Scene memory update cancelled.")
            throw CancellationError()
        } catch {
            finishTaskErrorToast(toastID, "Scene memory update failed.")
            throw error
        }
    }

    func updateSelectedChapterRollingMemory(_ summary: String) {
        guard let selectedChapterID else { return }
        updateRollingChapterMemory(chapterID: selectedChapterID, summary: summary)
        saveProject(debounced: true)
    }

    func refreshSelectedChapterRollingMemory(from sourceText: String) async throws -> String {
        guard let chapter = selectedChapter else {
            throw AIServiceError.badResponse("Select a chapter first.")
        }

        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            throw AIServiceError.badResponse("Source text is empty.")
        }

        let chapterTitle = displayChapterTitle(chapter)
        let sourceExcerpt = String(trimmedSource.prefix(Self.rollingChapterMemorySourceChars))
        let existingMemory = rollingChapterSummary(for: chapter.id)
        let toastID = startTaskProgressToast("Updating chapter memory…")

        do {
            let normalizedSummary = try await mergeChapterRollingMemory(
                chapterTitle: chapterTitle,
                existingMemory: existingMemory,
                sourceText: sourceExcerpt
            )

            updateRollingChapterMemory(chapterID: chapter.id, summary: normalizedSummary)
            saveProject(debounced: true)
            finishTaskSuccessToast(toastID, "Chapter memory updated.")
            return normalizedSummary
        } catch is CancellationError {
            finishTaskCancelledToast(toastID, "Chapter memory update cancelled.")
            throw CancellationError()
        } catch {
            finishTaskErrorToast(toastID, "Chapter memory update failed.")
            throw error
        }
    }

    func refreshSelectedChapterRollingMemoryFromScenes(
        _ source: ChapterRollingMemorySceneSource,
        onIteration: ((String, Int, Int) -> Void)? = nil
    ) async throws -> String {
        guard let chapter = selectedChapter else {
            throw AIServiceError.badResponse("Select a chapter first.")
        }

        let chunks = try chapterMemorySourceChunks(chapter: chapter, source: source)
        guard !chunks.isEmpty else {
            throw AIServiceError.badResponse("Source text is empty.")
        }

        let chapterTitle = displayChapterTitle(chapter)
        var memory = rollingChapterSummary(for: chapter.id)
        var toastID = startTaskProgressToast("Updating chapter memory (0/\(chunks.count))…")

        do {
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                memory = try await mergeChapterRollingMemory(
                    chapterTitle: chapterTitle,
                    existingMemory: memory,
                    sourceText: chunk.text,
                    sourceLabel: chunk.label
                )
                onIteration?(memory, index + 1, chunks.count)
                if let existingID = toastID {
                    toastID = showTaskNotification(
                        "Updating chapter memory (\(index + 1)/\(chunks.count))…",
                        style: .progress,
                        updating: existingID,
                        autoDismiss: false
                    )
                }
            }

            updateRollingChapterMemory(chapterID: chapter.id, summary: memory)
            saveProject(debounced: true)
            finishTaskSuccessToast(toastID, "Chapter memory updated.")
            return memory
        } catch is CancellationError {
            finishTaskCancelledToast(toastID, "Chapter memory update cancelled.")
            throw CancellationError()
        } catch {
            finishTaskErrorToast(toastID, "Chapter memory update failed.")
            throw error
        }
    }

    func updateSelectedChapterSummary(_ summary: String) {
        guard let selectedChapterID else {
            return
        }
        updateChapterSummary(chapterID: selectedChapterID, summary: summary, debounced: true)
    }

    func updateProjectNotes(_ notes: String) {
        project.notes = notes
        saveProject(debounced: true)
    }

    func updateSelectedSceneNotes(_ notes: String) {
        guard let selectedSceneID else {
            return
        }
        updateSceneNotes(sceneID: selectedSceneID, notes: notes, debounced: true)
    }

    func updateSelectedChapterNotes(_ notes: String) {
        guard let selectedChapterID else {
            return
        }
        updateChapterNotes(chapterID: selectedChapterID, notes: notes, debounced: true)
    }

    private func updateSceneSummary(sceneID: UUID, summary: String, debounced: Bool) {
        guard let location = sceneLocation(for: sceneID) else {
            return
        }

        project.chapters[location.chapterIndex].scenes[location.sceneIndex].summary = summary
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].updatedAt = .now
        project.chapters[location.chapterIndex].updatedAt = .now
        saveProject(debounced: debounced)
    }

    private func updateChapterSummary(chapterID: UUID, summary: String, debounced: Bool) {
        guard let chapterIndex = chapterIndex(for: chapterID) else {
            return
        }

        project.chapters[chapterIndex].summary = summary
        project.chapters[chapterIndex].updatedAt = .now
        saveProject(debounced: debounced)
    }

    private func updateSceneNotes(sceneID: UUID, notes: String, debounced: Bool) {
        guard let location = sceneLocation(for: sceneID) else {
            return
        }

        project.chapters[location.chapterIndex].scenes[location.sceneIndex].notes = notes
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].updatedAt = .now
        project.chapters[location.chapterIndex].updatedAt = .now
        saveProject(debounced: debounced)
    }

    private func updateChapterNotes(chapterID: UUID, notes: String, debounced: Bool) {
        guard let chapterIndex = chapterIndex(for: chapterID) else {
            return
        }

        project.chapters[chapterIndex].notes = notes
        project.chapters[chapterIndex].updatedAt = .now
        saveProject(debounced: debounced)
    }

    // MARK: - Compendium

    func addCompendiumEntry(category: CompendiumCategory) {
        let entry = CompendiumEntry(
            category: category,
            title: "New \(category.label.dropLast(category.label.hasSuffix("s") ? 1 : 0))"
        )

        project.compendium.append(entry)
        selectedCompendiumID = entry.id
        saveProject()
    }

    func duplicateSelectedCompendiumEntry() {
        guard let selectedCompendiumID,
              let source = project.compendium.first(where: { $0.id == selectedCompendiumID }) else {
            return
        }

        let copy = CompendiumEntry(
            category: source.category,
            title: source.title + " Copy",
            body: source.body,
            tags: source.tags
        )

        project.compendium.append(copy)
        self.selectedCompendiumID = copy.id
        saveProject()
    }

    func deleteSelectedCompendiumEntry() {
        guard let selectedCompendiumID else { return }
        project.compendium.removeAll { $0.id == selectedCompendiumID }
        removeCompendiumEntryFromSceneContextSelections(selectedCompendiumID)
        self.selectedCompendiumID = project.compendium.first?.id
        saveProject()
    }

    func clearCompendium() {
        for entry in project.compendium {
            removeCompendiumEntryFromSceneContextSelections(entry.id)
        }
        project.compendium.removeAll()
        selectedCompendiumID = nil
        saveProject()
    }

    func updateSelectedCompendiumTitle(_ title: String) {
        guard let selectedCompendiumID,
              let index = compendiumIndex(for: selectedCompendiumID) else {
            return
        }

        project.compendium[index].title = title
        project.compendium[index].updatedAt = .now
        saveProject(debounced: true)
    }

    func updateSelectedCompendiumBody(_ body: String) {
        guard let selectedCompendiumID,
              let index = compendiumIndex(for: selectedCompendiumID) else {
            return
        }

        project.compendium[index].body = body
        project.compendium[index].updatedAt = .now
        saveProject(debounced: true)
    }

    func updateSelectedCompendiumTags(from csv: String) {
        guard let selectedCompendiumID,
              let index = compendiumIndex(for: selectedCompendiumID) else {
            return
        }

        let tags = csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        project.compendium[index].tags = tags
        project.compendium[index].updatedAt = .now
        saveProject(debounced: true)
    }

    // MARK: - Prose Generation

    func applyBeatInputFromHistory(_ text: String) {
        beatInput = text
    }

    func submitBeatGeneration(
        modelsOverride: [String]? = nil,
        candidateIDsByModel: [String: UUID] = [:],
        beatOverride: String? = nil,
        sceneIDOverride: UUID? = nil
    ) {
        guard proseRequestTask == nil else { return }

        proseRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.proseRequestTask = nil
            }
            await self.generateFromBeat(
                modelsOverride: modelsOverride,
                candidateIDsByModel: candidateIDsByModel,
                beatOverride: beatOverride,
                sceneIDOverride: sceneIDOverride
            )
        }
    }

    func cancelBeatGeneration() {
        proseRequestTask?.cancel()
        generationStatus = "Cancelling..."
    }

    func dismissProseGenerationReview() {
        if isGenerating {
            cancelBeatGeneration()
        }
        proseGenerationReview = nil
        proseGenerationSessionContext = nil
    }

    func retryAllProseGenerationCandidates() {
        guard !isGenerating else { return }
        guard let review = proseGenerationReview else { return }
        guard let context = proseGenerationSessionContext else { return }
        let models = review.candidates.map(\.model)
        let idMap = Dictionary(uniqueKeysWithValues: review.candidates.map { ($0.model, $0.id) })
        submitBeatGeneration(
            modelsOverride: models,
            candidateIDsByModel: idMap,
            beatOverride: context.beat,
            sceneIDOverride: context.sceneID
        )
    }

    func retryProseGenerationCandidate(_ candidateID: UUID) {
        guard !isGenerating else { return }
        guard let review = proseGenerationReview,
              let context = proseGenerationSessionContext,
              let candidate = review.candidates.first(where: { $0.id == candidateID }) else {
            return
        }
        submitBeatGeneration(
            modelsOverride: [candidate.model],
            candidateIDsByModel: [candidate.model: candidate.id],
            beatOverride: context.beat,
            sceneIDOverride: context.sceneID
        )
    }

    func acceptProseGenerationCandidate(_ candidateID: UUID) {
        guard let review = proseGenerationReview,
              let candidate = review.candidates.first(where: { $0.id == candidateID }),
              candidate.status == .completed else {
            return
        }

        appendGeneratedText(candidate.text)
        proseLiveUsage = candidate.usage
        generationStatus = "Inserted output from \(candidate.model)."
        beatInput = ""
        proseGenerationReview = nil
        proseGenerationSessionContext = nil
        saveProject()
    }

    func makeProsePayloadPreview() throws -> WorkshopPayloadPreview {
        let beat = beatInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let scene = selectedScene else {
            throw AIServiceError.badResponse("Select a scene first.")
        }

        let previewModel = resolveGenerationModelSelection(modelsOverride: nil).first
        let requestBuild = makeProseGenerationRequest(beat: beat, scene: scene, modelOverride: previewModel)
        let request = requestBuild.request
        var baseNotes = [
            "Prompt includes beat input, current scene excerpt, and selected scene context entries.",
            "Preview request model: \(request.model).",
            "Streaming is \(project.settings.enableStreaming ? "enabled" : "disabled").",
            "Candidate-review generation runs in non-streaming mode.",
            "Timeout is \(Int(project.settings.requestTimeoutSeconds.rounded())) seconds."
        ]
        if beat.isEmpty {
            baseNotes.append("Beat input is empty. Prompt relies on template/context without beat guidance.")
        }
        let notes = previewNotes(base: baseNotes, renderWarnings: requestBuild.renderWarnings)

        switch project.settings.provider {
        case .anthropic:
            let preview = try anthropicService.makeRequestPreview(request: request, settings: project.settings)
            return WorkshopPayloadPreview(
                providerLabel: project.settings.provider.label,
                endpointURL: preview.url,
                method: preview.method,
                headers: preview.headers,
                bodyJSON: preview.bodyJSON,
                bodyHumanReadable: preview.bodyHumanReadable,
                notes: notes
            )
        case .openAI, .openRouter, .lmStudio, .openAICompatible:
            let preview = try openAIService.makeChatRequestPreview(request: request, settings: project.settings)
            return WorkshopPayloadPreview(
                providerLabel: project.settings.provider.label,
                endpointURL: preview.url,
                method: preview.method,
                headers: preview.headers,
                bodyJSON: preview.bodyJSON,
                bodyHumanReadable: preview.bodyHumanReadable,
                notes: notes
            )
        }
    }

    func makeRewritePayloadPreview(selectedText: String) throws -> WorkshopPayloadPreview {
        let normalizedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSelection.isEmpty else {
            throw AIServiceError.badResponse("Select scene text to preview rewrite payload.")
        }

        guard let scene = selectedScene else {
            throw AIServiceError.badResponse("Select a scene first.")
        }

        let requestBuild = makeRewriteRequest(selectedText: normalizedSelection, scene: scene)
        let request = requestBuild.request
        let notes = previewNotes(
            base: [
                "Prompt includes selected text, local selection context, current scene excerpt, and selected scene context entries.",
                "Preview request model: \(request.model).",
                "Streaming is \(project.settings.enableStreaming ? "enabled" : "disabled").",
                "Timeout is \(Int(project.settings.requestTimeoutSeconds.rounded())) seconds."
            ],
            renderWarnings: requestBuild.renderWarnings
        )

        switch project.settings.provider {
        case .anthropic:
            let preview = try anthropicService.makeRequestPreview(request: request, settings: project.settings)
            return WorkshopPayloadPreview(
                providerLabel: project.settings.provider.label,
                endpointURL: preview.url,
                method: preview.method,
                headers: preview.headers,
                bodyJSON: preview.bodyJSON,
                bodyHumanReadable: preview.bodyHumanReadable,
                notes: notes
            )
        case .openAI, .openRouter, .lmStudio, .openAICompatible:
            let preview = try openAIService.makeChatRequestPreview(request: request, settings: project.settings)
            return WorkshopPayloadPreview(
                providerLabel: project.settings.provider.label,
                endpointURL: preview.url,
                method: preview.method,
                headers: preview.headers,
                bodyJSON: preview.bodyJSON,
                bodyHumanReadable: preview.bodyHumanReadable,
                notes: notes
            )
        }
    }

    func rewriteSelectedSceneText(
        _ selectedText: String,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        let normalizedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSelection.isEmpty else {
            throw AIServiceError.badResponse("Select some scene text first.")
        }
        guard let scene = selectedScene else {
            throw AIServiceError.badResponse("Select a scene first.")
        }

        let request = makeRewriteRequest(selectedText: normalizedSelection, scene: scene).request
        generationStatus = shouldUseStreaming ? "Rewriting..." : "Rewriting..."
        proseLiveUsage = normalizedTokenUsage(from: nil, request: request, response: "")
        let toastID = startTaskProgressToast("Rewriting selected text…")

        let rewritePartialHandler: (@MainActor (String) -> Void)?
        if shouldUseStreaming {
            rewritePartialHandler = { [weak self, onPartial] partial in
                guard let self else { return }
                self.generationStatus = "Rewriting..."
                self.proseLiveUsage = self.normalizedTokenUsage(from: nil, request: request, response: partial)
                onPartial?(partial)
            }
        } else {
            rewritePartialHandler = nil
        }

        do {
            let result = try await generateTextResult(
                request,
                onPartial: rewritePartialHandler
            )
            let normalizedRewrite = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedRewrite.isEmpty else {
                throw AIServiceError.badResponse("Rewrite result was empty.")
            }

            proseLiveUsage = normalizedTokenUsage(from: result.usage, request: request, response: normalizedRewrite)
            generationStatus = "Rewrote \(normalizedRewrite.count) characters."
            finishTaskSuccessToast(toastID, "Rewrite completed.")
            return normalizedRewrite
        } catch is CancellationError {
            generationStatus = "Rewrite cancelled."
            finishTaskCancelledToast(toastID, "Rewrite cancelled.")
            throw CancellationError()
        } catch {
            proseLiveUsage = nil
            generationStatus = "Rewrite failed."
            finishTaskErrorToast(toastID, "Rewrite failed.")
            throw error
        }
    }

    func summarizeSelectedScene() async throws -> String {
        guard let scene = selectedScene else {
            throw AIServiceError.badResponse("Select a scene first.")
        }

        let sceneID = scene.id
        let request = makeSummaryRequest(scene: scene).request
        updateSceneSummary(sceneID: sceneID, summary: "", debounced: true)
        let toastID = startTaskProgressToast("Summarizing scene…")

        let summaryPartialHandler: (@MainActor (String) -> Void)?
        if shouldUseStreaming {
            summaryPartialHandler = { [weak self] partial in
                guard let self else { return }
                self.updateSceneSummary(sceneID: sceneID, summary: partial, debounced: true)
            }
        } else {
            summaryPartialHandler = nil
        }

        do {
            let result = try await generateTextResult(request, onPartial: summaryPartialHandler)
            let normalizedSummary = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedSummary.isEmpty else {
                throw AIServiceError.badResponse("Summary result was empty.")
            }

            updateSceneSummary(sceneID: sceneID, summary: normalizedSummary, debounced: false)
            updateRollingSceneMemory(
                sceneID: sceneID,
                summary: normalizedSummary,
                sourceContent: scene.content
            )
            finishTaskSuccessToast(toastID, "Scene summary updated.")
            return normalizedSummary
        } catch is CancellationError {
            finishTaskCancelledToast(toastID, "Scene summarization cancelled.")
            throw CancellationError()
        } catch {
            finishTaskErrorToast(toastID, "Scene summarization failed.")
            throw error
        }
    }

    func summarizeSelectedChapter() async throws -> String {
        guard let chapter = selectedChapter else {
            throw AIServiceError.badResponse("Select a chapter first.")
        }

        let chapterID = chapter.id
        let request = makeChapterSummaryRequest(chapter: chapter).request
        updateChapterSummary(chapterID: chapterID, summary: "", debounced: true)
        let toastID = startTaskProgressToast("Summarizing chapter…")

        let summaryPartialHandler: (@MainActor (String) -> Void)?
        if shouldUseStreaming {
            summaryPartialHandler = { [weak self] partial in
                guard let self else { return }
                self.updateChapterSummary(chapterID: chapterID, summary: partial, debounced: true)
            }
        } else {
            summaryPartialHandler = nil
        }

        do {
            let result = try await generateTextResult(request, onPartial: summaryPartialHandler)
            let normalizedSummary = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedSummary.isEmpty else {
                throw AIServiceError.badResponse("Summary result was empty.")
            }

            updateChapterSummary(chapterID: chapterID, summary: normalizedSummary, debounced: false)
            updateRollingChapterMemory(chapterID: chapterID, summary: normalizedSummary)
            finishTaskSuccessToast(toastID, "Chapter summary updated.")
            return normalizedSummary
        } catch is CancellationError {
            finishTaskCancelledToast(toastID, "Chapter summarization cancelled.")
            throw CancellationError()
        } catch {
            finishTaskErrorToast(toastID, "Chapter summarization failed.")
            throw error
        }
    }

    // MARK: - Workshop

    func applyWorkshopInputFromHistory(_ text: String) {
        workshopInput = text
    }

    func updateSelectedWorkshopRollingMemory(_ summary: String) {
        guard let selectedWorkshopSessionID else { return }
        updateWorkshopRollingMemory(
            sessionID: selectedWorkshopSessionID,
            summary: summary,
            summarizedMessageCount: selectedWorkshopSession?.messages.count ?? 0
        )
    }

    func makeWorkshopPayloadPreview() throws -> WorkshopPayloadPreview {
        guard let sessionID = selectedWorkshopSessionID else {
            throw AIServiceError.badResponse("Select a chat session first.")
        }

        let pendingUserInput = workshopInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptResult = buildWorkshopUserPrompt(
            sessionID: sessionID,
            pendingUserInput: pendingUserInput.isEmpty ? nil : pendingUserInput
        )

        let request = TextGenerationRequest(
            systemPrompt: resolvedWorkshopSystemPrompt(),
            userPrompt: promptResult.renderedText,
            model: resolvedPrimaryModel(),
            temperature: project.settings.temperature,
            maxTokens: project.settings.maxTokens
        )

        var baseNotes = [
            "Streaming is \(project.settings.enableStreaming ? "enabled" : "disabled").",
            "Timeout is \(Int(project.settings.requestTimeoutSeconds.rounded())) seconds."
        ]
        if pendingUserInput.isEmpty {
            baseNotes.append("Workshop input is empty. Preview uses the current chat/context without a new user turn.")
        }
        let notes = previewNotes(base: baseNotes, renderWarnings: promptResult.warnings)

        switch project.settings.provider {
        case .anthropic:
            let preview = try anthropicService.makeRequestPreview(request: request, settings: project.settings)
            return WorkshopPayloadPreview(
                providerLabel: project.settings.provider.label,
                endpointURL: preview.url,
                method: preview.method,
                headers: preview.headers,
                bodyJSON: preview.bodyJSON,
                bodyHumanReadable: preview.bodyHumanReadable,
                notes: notes
            )
        case .openAI, .openRouter, .lmStudio, .openAICompatible:
            let preview = try openAIService.makeChatRequestPreview(request: request, settings: project.settings)
            return WorkshopPayloadPreview(
                providerLabel: project.settings.provider.label,
                endpointURL: preview.url,
                method: preview.method,
                headers: preview.headers,
                bodyJSON: preview.bodyJSON,
                bodyHumanReadable: preview.bodyHumanReadable,
                notes: notes
            )
        }
    }

    func submitWorkshopMessage() {
        guard workshopRequestTask == nil else { return }

        workshopRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.workshopRequestTask = nil
            }
            await self.sendWorkshopMessage()
        }
    }

    func cancelWorkshopMessage() {
        workshopRequestTask?.cancel()
        workshopStatus = "Cancelling..."
    }

    func retryLastWorkshopTurn() {
        guard !workshopIsGenerating else { return }
        guard let sessionID = selectedWorkshopSessionID,
              let sessionIndex = workshopSessionIndex(for: sessionID) else {
            workshopStatus = "Select a chat session first."
            return
        }

        let messages = project.workshopSessions[sessionIndex].messages
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else {
            workshopStatus = "No user message to retry."
            return
        }

        let userText = messages[lastUserIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else {
            workshopStatus = "Last user message is empty."
            return
        }

        project.workshopSessions[sessionIndex].messages.removeSubrange(lastUserIndex..<messages.endIndex)
        project.workshopSessions[sessionIndex].updatedAt = .now

        workshopInput = userText
        workshopStatus = "Retrying last prompt..."
        saveProject()
        submitWorkshopMessage()
    }

    func deleteLastWorkshopAssistantMessage() {
        guard !workshopIsGenerating else { return }
        guard let sessionID = selectedWorkshopSessionID,
              let sessionIndex = workshopSessionIndex(for: sessionID) else {
            return
        }

        guard let assistantIndex = project.workshopSessions[sessionIndex].messages.lastIndex(where: { $0.role == .assistant }) else {
            workshopStatus = "No assistant message to delete."
            return
        }

        project.workshopSessions[sessionIndex].messages.remove(at: assistantIndex)
        project.workshopSessions[sessionIndex].updatedAt = .now
        workshopStatus = "Deleted last assistant message."
        saveProject()
    }

    func deleteLastWorkshopUserTurn() {
        guard !workshopIsGenerating else { return }
        guard let sessionID = selectedWorkshopSessionID,
              let sessionIndex = workshopSessionIndex(for: sessionID) else {
            return
        }

        let messages = project.workshopSessions[sessionIndex].messages
        guard let userIndex = messages.lastIndex(where: { $0.role == .user }) else {
            workshopStatus = "No user message to delete."
            return
        }

        project.workshopSessions[sessionIndex].messages.removeSubrange(userIndex..<messages.endIndex)
        project.workshopSessions[sessionIndex].updatedAt = .now
        workshopStatus = "Deleted last user turn."
        saveProject()
    }

    func createWorkshopSession() {
        let nextIndex = project.workshopSessions.count + 1
        var session = Self.makeInitialWorkshopSession(name: "Chat \(nextIndex)")
        session.useSceneContext = workshopUseSceneContext
        session.useCompendiumContext = workshopUseCompendiumContext
        project.workshopSessions.append(session)
        selectedWorkshopSessionID = session.id
        project.selectedWorkshopSessionID = session.id
        syncWorkshopContextTogglesFromSelectedSession()
        saveProject()
    }

    func canDeleteWorkshopSession(_ sessionID: UUID) -> Bool {
        project.workshopSessions.count > 1 && workshopSessionIndex(for: sessionID) != nil
    }

    func deleteWorkshopSession(_ sessionID: UUID) {
        guard canDeleteWorkshopSession(sessionID) else { return }
        workshopRollingMemoryTask?.cancel()
        project.workshopSessions.removeAll { $0.id == sessionID }
        project.rollingWorkshopMemoryBySession.removeValue(forKey: sessionID.uuidString)
        ensureValidSelections()
        saveProject()
    }

    func clearWorkshopSessionMessages(_ sessionID: UUID) {
        guard let index = workshopSessionIndex(for: sessionID) else { return }
        workshopRollingMemoryTask?.cancel()
        project.workshopSessions[index].messages = []
        project.workshopSessions[index].updatedAt = .now
        project.rollingWorkshopMemoryBySession.removeValue(forKey: sessionID.uuidString)
        saveProject()
    }

    func renameWorkshopSession(_ sessionID: UUID, to name: String) {
        guard let index = workshopSessionIndex(for: sessionID) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        project.workshopSessions[index].name = trimmed.isEmpty ? "Untitled Chat" : trimmed
        project.workshopSessions[index].updatedAt = .now
        saveProject(debounced: true)
    }

    func sendWorkshopMessage() async {
        guard !Task.isCancelled else { return }

        let userText = workshopInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workshopIsGenerating else { return }
        guard let sessionID = selectedWorkshopSessionID,
              let sessionIndex = workshopSessionIndex(for: sessionID) else {
            workshopStatus = "Select a chat session first."
            return
        }

        if !userText.isEmpty {
            rememberWorkshopInputHistory(userText, for: sessionID)
            appendWorkshopMessage(.init(role: .user, content: userText), to: sessionID)
        }
        workshopInput = ""
        workshopIsGenerating = true
        workshopLiveUsage = nil
        workshopStatus = shouldUseStreaming ? "Streaming..." : "Thinking..."
        let toastID = startTaskProgressToast("Generating workshop response…")

        let prompt = buildWorkshopUserPrompt(sessionID: sessionID).renderedText
        let systemPrompt = resolvedWorkshopSystemPrompt()

        var streamingAssistantMessageID: UUID?
        if shouldUseStreaming {
            let placeholder = WorkshopMessage(role: .assistant, content: "")
            streamingAssistantMessageID = placeholder.id
            appendWorkshopMessage(placeholder, to: sessionID)
        }

        let request = TextGenerationRequest(
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            model: resolvedPrimaryModel(),
            temperature: project.settings.temperature,
            maxTokens: project.settings.maxTokens
        )

        defer {
            workshopIsGenerating = false
            workshopLiveUsage = nil
        }

        let workshopPartialHandler: (@MainActor (String) -> Void)?
        if shouldUseStreaming {
            workshopStreamingLastPublishDate = .distantPast
            workshopPartialHandler = { [weak self] partial in
                guard let self, let messageID = streamingAssistantMessageID else { return }
                let now = Date()
                guard now.timeIntervalSince(self.workshopStreamingLastPublishDate) >= self.workshopStreamingPublishInterval else { return }
                self.workshopStreamingLastPublishDate = now
                self.updateWorkshopMessageContent(sessionID: sessionID, messageID: messageID, content: partial)
                self.workshopLiveUsage = self.normalizedTokenUsage(
                    from: nil,
                    request: request,
                    response: partial
                )
            }
            workshopLiveUsage = normalizedTokenUsage(from: nil, request: request, response: "")
        } else {
            workshopPartialHandler = nil
        }

        do {
            let result = try await generateTextResult(
                request,
                onPartial: workshopPartialHandler
            )
            let response = result.text
            let usage = normalizedTokenUsage(
                from: result.usage,
                request: request,
                response: response
            )

            if shouldUseStreaming, let messageID = streamingAssistantMessageID {
                updateWorkshopMessageContent(sessionID: sessionID, messageID: messageID, content: response)
                updateWorkshopMessageUsage(sessionID: sessionID, messageID: messageID, usage: usage)
            } else {
                appendWorkshopMessage(
                    .init(role: .assistant, content: response, usage: usage),
                    to: sessionID
                )
            }

            workshopStatus = "Response generated."
            project.workshopSessions[sessionIndex].updatedAt = .now
            saveProject()
            finishTaskSuccessToast(toastID, "Workshop response generated.")
            scheduleWorkshopRollingMemoryRefresh(for: sessionID)
        } catch is CancellationError {
            workshopStatus = "Request cancelled."

            if shouldUseStreaming, let messageID = streamingAssistantMessageID {
                removeWorkshopMessageIfEmpty(sessionID: sessionID, messageID: messageID)
            }

            saveProject()
            finishTaskCancelledToast(toastID, "Workshop request cancelled.")
        } catch {
            workshopStatus = "Chat request failed."
            lastError = error.localizedDescription

            let errorMessage = "I hit an error: \(error.localizedDescription)"
            if shouldUseStreaming, let messageID = streamingAssistantMessageID {
                updateWorkshopMessageContent(sessionID: sessionID, messageID: messageID, content: errorMessage)
            } else {
                appendWorkshopMessage(
                    .init(role: .assistant, content: errorMessage),
                    to: sessionID
                )
            }
            saveProject()
            finishTaskErrorToast(toastID, "Workshop request failed.")
        }
    }

    // MARK: - Prompts

    func setSelectedProsePrompt(_ id: UUID?) {
        project.selectedProsePromptID = id
        saveProject(debounced: true)
    }

    func setSelectedRewritePrompt(_ id: UUID?) {
        project.selectedRewritePromptID = id
        saveProject(debounced: true)
    }

    func setSelectedSummaryPrompt(_ id: UUID?) {
        project.selectedSummaryPromptID = id
        saveProject(debounced: true)
    }

    func setSelectedWorkshopPrompt(_ id: UUID?) {
        project.selectedWorkshopPromptID = id
        saveProject(debounced: true)
    }

    @discardableResult
    func addPrompt(category: PromptCategory) -> UUID {
        let categoryPrompts = prompts(in: category)
        let defaults = defaultPromptTemplate(for: category)
        let titleBase = promptTitleBase(for: category)

        let prompt = PromptTemplate(
            category: category,
            title: "\(titleBase) \(categoryPrompts.count + 1)",
            userTemplate: defaults.userTemplate,
            systemTemplate: defaults.systemTemplate
        )

        project.prompts.append(prompt)
        switch category {
        case .prose:
            project.selectedProsePromptID = prompt.id
        case .rewrite:
            project.selectedRewritePromptID = prompt.id
        case .summary:
            project.selectedSummaryPromptID = prompt.id
        case .workshop:
            project.selectedWorkshopPromptID = prompt.id
        }

        saveProject()
        return prompt.id
    }

    @discardableResult
    func deletePrompt(_ promptID: UUID) -> Bool {
        guard let index = promptIndex(for: promptID) else {
            return false
        }

        let category = project.prompts[index].category
        let categoryCount = prompts(in: category).count
        guard categoryCount > 1 else {
            return false
        }

        project.prompts.remove(at: index)

        switch category {
        case .prose:
            if project.selectedProsePromptID == promptID {
                project.selectedProsePromptID = prompts(in: .prose).first?.id
            }
        case .rewrite:
            if project.selectedRewritePromptID == promptID {
                project.selectedRewritePromptID = prompts(in: .rewrite).first?.id
            }
        case .summary:
            if project.selectedSummaryPromptID == promptID {
                project.selectedSummaryPromptID = prompts(in: .summary).first?.id
            }
        case .workshop:
            if project.selectedWorkshopPromptID == promptID {
                project.selectedWorkshopPromptID = prompts(in: .workshop).first?.id
            }
        }

        saveProject()
        return true
    }

    func clearPrompts() {
        project.prompts.removeAll()
        project.selectedProsePromptID = nil
        project.selectedRewritePromptID = nil
        project.selectedSummaryPromptID = nil
        project.selectedWorkshopPromptID = nil
        saveProject()
    }

    func addProsePrompt() {
        _ = addPrompt(category: .prose)
    }

    func addWorkshopPrompt() {
        _ = addPrompt(category: .workshop)
    }

    func deleteSelectedProsePrompt() {
        guard let selected = project.selectedProsePromptID else { return }
        _ = deletePrompt(selected)
    }

    func deleteSelectedWorkshopPrompt() {
        guard let selected = project.selectedWorkshopPromptID else { return }
        _ = deletePrompt(selected)
    }

    func updatePromptTitle(_ promptID: UUID, value: String) {
        guard let index = promptIndex(for: promptID) else { return }
        project.prompts[index].title = value
        saveProject(debounced: true)
    }

    func updatePromptUserTemplate(_ promptID: UUID, value: String) {
        guard let index = promptIndex(for: promptID) else { return }
        project.prompts[index].userTemplate = value
        saveProject(debounced: true)
    }

    func updatePromptSystemTemplate(_ promptID: UUID, value: String) {
        guard let index = promptIndex(for: promptID) else { return }
        project.prompts[index].systemTemplate = value
        saveProject(debounced: true)
    }

    func makePromptTemplateRenderPreview(promptID: UUID) throws -> PromptTemplateRenderPreview {
        guard let index = promptIndex(for: promptID) else {
            throw AIServiceError.badResponse("Select a prompt template first.")
        }

        let prompt = project.prompts[index]
        let promptTitle = prompt.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Prompt"
            : prompt.title.trimmingCharacters(in: .whitespacesAndNewlines)

        var notes: [String] = []
        let scenePreview = resolvePromptPreviewSceneContext()
        if let sceneNote = scenePreview.note {
            notes.append(sceneNote)
        }

        let beatPreviewInput = beatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let beatPreview = beatPreviewInput.isEmpty
            ? "A quiet promise turns into a dangerous obligation."
            : beatPreviewInput
        if beatPreviewInput.isEmpty && (prompt.category == .prose || prompt.category == .rewrite) {
            notes.append("Beat input is empty. Preview used sample beat text.")
        }

        let selectionPreview = "She stared at the letter, then folded it into her coat."
        if prompt.category == .rewrite {
            notes.append("Rewrite preview used sample selected text (settings preview has no editor selection).")
        }

        let renderedUser: PromptRenderer.Result
        switch prompt.category {
        case .prose:
            let contextSections = buildCompendiumContextSections(
                for: scenePreview.sceneID,
                mentionSourceText: beatPreview
            )
            let sceneExcerpt = String(scenePreview.sceneContent.suffix(Self.proseSceneTailChars))
            let sceneSummary = sceneSummaryText(for: scenePreview.sceneID)
            renderedUser = renderPromptTemplate(
                template: prompt.userTemplate,
                fallbackTemplate: fallbackUserTemplate(for: prompt, category: .prose),
                beat: beatPreview,
                selection: "",
                sceneID: scenePreview.sceneID,
                sceneExcerpt: sceneExcerpt,
                sceneFullText: scenePreview.sceneContent,
                sceneTitle: scenePreview.sceneTitle,
                chapterTitle: scenePreview.chapterTitle,
                contextSections: contextSections,
                conversation: "",
                conversationTurns: [],
                summaryScope: "",
                source: sceneExcerpt,
                extraVariables: [
                    "scene_summary": sceneSummary
                ]
            )

        case .rewrite:
            let contextSections = buildCompendiumContextSections(
                for: scenePreview.sceneID,
                mentionSourceText: beatPreview
            )
            let sceneExcerpt = String(scenePreview.sceneContent.suffix(Self.rewriteSceneContextChars))
            let localSelectionContext = selectionLocalContext(
                selectedText: selectionPreview,
                in: scenePreview.sceneContent
            )
            renderedUser = renderPromptTemplate(
                template: prompt.userTemplate,
                fallbackTemplate: fallbackUserTemplate(for: prompt, category: .rewrite),
                beat: beatPreview,
                selection: selectionPreview,
                sceneID: scenePreview.sceneID,
                sceneExcerpt: sceneExcerpt,
                sceneFullText: scenePreview.sceneContent,
                sceneTitle: scenePreview.sceneTitle,
                chapterTitle: scenePreview.chapterTitle,
                contextSections: contextSections,
                conversation: "",
                conversationTurns: [],
                summaryScope: "",
                source: selectionPreview,
                extraVariables: [
                    "selection_context": localSelectionContext
                ]
            )

        case .summary:
            if scenePreview.sceneID != nil {
                let contextSections = buildCompendiumContextSections(for: scenePreview.sceneID)
                let scopeContext = """
                Scope: scene summary
                \(contextSections.combined)
                """
                let sceneExcerpt = String(scenePreview.sceneContent.suffix(Self.summarySourceChars))
                notes.append("Summary preview scope: scene.")
                renderedUser = renderPromptTemplate(
                    template: prompt.userTemplate,
                    fallbackTemplate: fallbackUserTemplate(for: prompt, category: .summary),
                    beat: "",
                    selection: "",
                    sceneID: scenePreview.sceneID,
                    sceneExcerpt: sceneExcerpt,
                    sceneFullText: scenePreview.sceneContent,
                    sceneTitle: scenePreview.sceneTitle,
                    chapterTitle: scenePreview.chapterTitle,
                    contextSections: SceneContextSections(
                        combined: scopeContext,
                        compendium: contextSections.compendium,
                        sceneSummaries: contextSections.sceneSummaries,
                        chapterSummaries: contextSections.chapterSummaries
                    ),
                    conversation: "",
                    conversationTurns: [],
                    summaryScope: "scene",
                    source: sceneExcerpt
                )
            } else if let chapter = selectedChapter ?? project.chapters.first {
                let chapterTitle = displayChapterTitle(chapter)
                let sceneSummaryContext = buildChapterSceneSummaryContext(chapter: chapter)
                let chapterContext = """
                Scope: chapter summary from scene summaries
                Chapter: \(chapterTitle)
                Scene count: \(chapter.scenes.count)
                """
                notes.append("Summary preview scope: chapter.")
                renderedUser = renderPromptTemplate(
                    template: prompt.userTemplate,
                    fallbackTemplate: fallbackUserTemplate(for: prompt, category: .summary),
                    beat: "",
                    selection: "",
                    sceneID: nil,
                    chapterID: chapter.id,
                    sceneExcerpt: sceneSummaryContext,
                    sceneFullText: sceneSummaryContext,
                    sceneTitle: "Chapter Summary Input",
                    chapterTitle: chapterTitle,
                    contextSections: SceneContextSections(
                        combined: chapterContext,
                        compendium: "",
                        sceneSummaries: sceneSummaryContext,
                        chapterSummaries: ""
                    ),
                    conversation: "",
                    conversationTurns: [],
                    summaryScope: "chapter",
                    source: sceneSummaryContext
                )
            } else {
                notes.append("No scene or chapter found. Summary preview uses placeholder source text.")
                renderedUser = renderPromptTemplate(
                    template: prompt.userTemplate,
                    fallbackTemplate: fallbackUserTemplate(for: prompt, category: .summary),
                    beat: "",
                    selection: "",
                    sceneID: nil,
                    sceneExcerpt: "No source text available.",
                    sceneFullText: "No source text available.",
                    sceneTitle: "No Scene",
                    chapterTitle: "No Chapter",
                    contextSections: SceneContextSections(
                        combined: "Scope: scene summary\nNo context available.",
                        compendium: "",
                        sceneSummaries: "",
                        chapterSummaries: ""
                    ),
                    conversation: "",
                    conversationTurns: [],
                    summaryScope: "scene",
                    source: "No source text available."
                )
            }

        case .workshop:
            var messages = (selectedWorkshopSession ?? project.workshopSessions.first)?.messages ?? []
            if messages.isEmpty {
                notes.append("Chat history is empty.")
            }

            let pendingInputRaw = workshopInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let pendingInput = pendingInputRaw.isEmpty
                ? "Give three options to raise tension in this scene."
                : pendingInputRaw
            if pendingInputRaw.isEmpty {
                notes.append("Chat input is empty. Preview appended sample user input.")
            }
            messages.append(.init(role: .user, content: pendingInput))

            let transcript = messages
                .suffix(14)
                .map { message in
                    let label = message.role == .user ? "User" : "Assistant"
                    return "\(label): \(message.content)"
                }
                .joined(separator: "\n\n")
            let conversationTurns = messages.map { message in
                PromptRenderer.ChatTurn(
                    roleLabel: message.role == .user ? "User" : "Assistant",
                    content: message.content
                )
            }

            let sceneContext = workshopUseSceneContext
                ? String(scenePreview.sceneContent.suffix(Self.workshopSceneTailChars))
                : ""
            let sceneFullText = workshopUseSceneContext ? scenePreview.sceneContent : ""

            let contextSections = buildCompendiumContextSections(
                for: scenePreview.sceneID,
                mentionSourceText: pendingInput,
                includeSelectedSceneContext: workshopUseCompendiumContext
            )

            let sessionName = (selectedWorkshopSession ?? project.workshopSessions.first)?.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedSessionName = (sessionName?.isEmpty == false) ? (sessionName ?? "") : "Untitled Chat"

            renderedUser = renderPromptTemplate(
                template: prompt.userTemplate,
                fallbackTemplate: fallbackUserTemplate(for: prompt, category: .workshop),
                beat: "",
                selection: pendingInput,
                sceneID: workshopUseSceneContext ? scenePreview.sceneID : nil,
                sceneExcerpt: sceneContext,
                sceneFullText: sceneFullText,
                sceneTitle: scenePreview.sceneTitle,
                chapterTitle: scenePreview.chapterTitle,
                contextSections: contextSections,
                conversation: transcript,
                conversationTurns: conversationTurns,
                summaryScope: "",
                source: transcript,
                workshopSessionID: selectedWorkshopSessionID,
                extraVariables: [
                    "chat_name": resolvedSessionName,
                    "last_user_message": messages.reversed().first(where: { $0.role == .user })?.content ?? "",
                    "last_assistant_message": messages.reversed().first(where: { $0.role == .assistant })?.content ?? ""
                ]
            )
        }

        let resolvedSystemPrompt = prompt.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? project.settings.defaultSystemPrompt
            : prompt.systemTemplate
        if prompt.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.append("System template is empty. Preview uses project default system prompt.")
        }

        return PromptTemplateRenderPreview(
            title: promptTitle,
            category: prompt.category,
            renderedUserPrompt: renderedUser.renderedText,
            resolvedSystemPrompt: resolvedSystemPrompt,
            notes: notes,
            warnings: renderedUser.warnings
        )
    }

    @discardableResult
    func refreshBuiltInPromptTemplatesToLatest() -> BuiltInPromptRefreshResult {
        var updatedCount = 0
        var addedCount = 0

        let latestBuiltIns = PromptTemplate.latestBuiltInTemplates(
            preferCompact: project.settings.preferCompactPromptTemplates
        )

        for builtIn in latestBuiltIns {
            if let index = promptIndex(for: builtIn.id) {
                if project.prompts[index] != builtIn {
                    project.prompts[index] = builtIn
                    updatedCount += 1
                }
            } else {
                project.prompts.append(builtIn)
                addedCount += 1
            }
        }

        ensureDefaultPromptSelections()
        if updatedCount > 0 || addedCount > 0 {
            saveProject()
        }

        return BuiltInPromptRefreshResult(
            updatedCount: updatedCount,
            addedCount: addedCount
        )
    }

    private func defaultPromptTemplate(for category: PromptCategory) -> PromptTemplate {
        let defaultID = defaultBuiltInPromptID(for: category)
        if let builtIn = latestBuiltInTemplate(for: defaultID) {
            return builtIn
        }

        switch category {
        case .prose:
            return PromptTemplate.defaultProseTemplate
        case .workshop:
            return PromptTemplate.defaultWorkshopTemplate
        case .rewrite:
            return PromptTemplate.defaultRewriteTemplate
        case .summary:
            return PromptTemplate.defaultSummaryTemplate
        }
    }

    private func defaultBuiltInPromptID(for category: PromptCategory) -> UUID {
        switch category {
        case .prose:
            return PromptTemplate.defaultProseTemplate.id
        case .workshop:
            return PromptTemplate.defaultWorkshopTemplate.id
        case .rewrite:
            return PromptTemplate.defaultRewriteTemplate.id
        case .summary:
            return PromptTemplate.defaultSummaryTemplate.id
        }
    }

    private func latestBuiltInTemplate(for templateID: UUID) -> PromptTemplate? {
        PromptTemplate.latestBuiltInTemplates(
            preferCompact: project.settings.preferCompactPromptTemplates
        )
        .first(where: { $0.id == templateID })
    }

    private func fallbackUserTemplate(for prompt: PromptTemplate, category: PromptCategory) -> String {
        if let builtIn = latestBuiltInTemplate(for: prompt.id) {
            return builtIn.userTemplate
        }
        return defaultPromptTemplate(for: category).userTemplate
    }

    private func promptTitleBase(for category: PromptCategory) -> String {
        switch category {
        case .prose:
            return "Writing Prompt"
        case .workshop:
            return "Chat Prompt"
        case .rewrite:
            return "Rewrite Prompt"
        case .summary:
            return "Summary Prompt"
        }
    }

    // MARK: - Generation

    func generateFromBeat(
        modelsOverride: [String]? = nil,
        candidateIDsByModel: [String: UUID] = [:],
        beatOverride: String? = nil,
        sceneIDOverride: UUID? = nil
    ) async {
        let beat = (beatOverride ?? beatInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isGenerating else { return }
        let scene: Scene?
        if let sceneIDOverride, let location = sceneLocation(for: sceneIDOverride) {
            scene = project.chapters[location.chapterIndex].scenes[location.sceneIndex]
        } else {
            scene = selectedScene
        }

        guard let scene else {
            generationStatus = "Select a scene first."
            return
        }

        if project.settings.useInlineGeneration {
            let model = resolveGenerationModelSelection(modelsOverride: modelsOverride).first
            await generateFromBeatInline(
                beat: beat,
                scene: scene,
                modelOverride: model
            )
            return
        }

        let modelIDs = resolveGenerationModelSelection(modelsOverride: modelsOverride)
        guard !modelIDs.isEmpty else {
            generationStatus = "Select at least one model."
            return
        }

        var renderWarnings: [String] = []
        let candidateRequests: [ProseCandidateRequestInput] = modelIDs.map { model in
            let requestBuild = makeProseGenerationRequest(beat: beat, scene: scene, modelOverride: model)
            renderWarnings.append(contentsOf: requestBuild.renderWarnings)
            let candidateID = candidateIDsByModel[model] ?? UUID()
            return ProseCandidateRequestInput(
                candidateID: candidateID,
                model: model,
                request: requestBuild.request
            )
        }
        renderWarnings = Array(Set(renderWarnings))

        let sceneTitle = displaySceneTitle(scene)
        let promptTitleRaw = activeProsePrompt?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let promptTitle = promptTitleRaw.isEmpty ? "Writing Prompt" : promptTitleRaw

        let reviewID: UUID
        if !candidateIDsByModel.isEmpty, var existing = proseGenerationReview {
            existing.beat = beat
            existing.sceneTitle = sceneTitle
            existing.promptTitle = promptTitle
            existing.renderWarnings = renderWarnings
            existing.startedAt = .now
            existing.isRunning = true

            for input in candidateRequests {
                if let index = existing.candidates.firstIndex(where: { $0.id == input.candidateID }) {
                    existing.candidates[index].status = .running
                    existing.candidates[index].text = ""
                    existing.candidates[index].usage = nil
                    existing.candidates[index].errorMessage = nil
                    existing.candidates[index].elapsedSeconds = nil
                } else {
                    existing.candidates.append(
                        ProseGenerationCandidate(
                            id: input.candidateID,
                            model: input.model,
                            status: .running,
                            text: "",
                            usage: nil,
                            errorMessage: nil,
                            elapsedSeconds: nil
                        )
                    )
                }
            }

            proseGenerationReview = existing
            reviewID = existing.id
        } else {
            reviewID = UUID()
            proseGenerationReview = ProseGenerationReviewState(
                id: reviewID,
                beat: beat,
                sceneTitle: sceneTitle,
                promptTitle: promptTitle,
                renderWarnings: renderWarnings,
                candidates: candidateRequests.map { input in
                    ProseGenerationCandidate(
                        id: input.candidateID,
                        model: input.model,
                        status: .running,
                        text: "",
                        usage: nil,
                        errorMessage: nil,
                        elapsedSeconds: nil
                    )
                },
                startedAt: .now,
                isRunning: true
            )
        }

        proseGenerationSessionContext = ProseGenerationSessionContext(
            reviewID: reviewID,
            sceneID: scene.id,
            beat: beat
        )
        rememberBeatInputHistory(beat, for: scene.id)

        isGenerating = true
        proseLiveUsage = nil
        generationStatus = "Generating 0/\(candidateRequests.count)..."
        var toastID = startTaskProgressToast("Generating candidates (0/\(candidateRequests.count))…")

        defer {
            isGenerating = false
        }

        let settingsForRun = project.settings
        let streamCandidates = shouldUseStreaming

        let provider = project.settings.provider
        let openAIService = openAIService
        let anthropicService = anthropicService
        var completed = 0
        let total = candidateRequests.count

        await withTaskGroup(of: ProseCandidateRunResult.self) { group in
            for input in candidateRequests {
                group.addTask {
                    let started = Date()
                    let partialHandler: (@MainActor (String) -> Void)?
                    if streamCandidates {
                        partialHandler = { [weak self] partial in
                            guard let self else { return }
                            self.updateProseCandidatePartial(
                                candidateID: input.candidateID,
                                partial: partial,
                                request: input.request,
                                reviewID: reviewID,
                                startedAt: started
                            )
                        }
                    } else {
                        partialHandler = nil
                    }
                    do {
                        let result: TextGenerationResult
                        switch provider {
                        case .anthropic:
                            result = try await anthropicService.generateTextResult(
                                input.request,
                                settings: settingsForRun,
                                onPartial: partialHandler
                            )
                        case .openAI, .openRouter, .lmStudio, .openAICompatible:
                            result = try await openAIService.generateTextResult(
                                input.request,
                                settings: settingsForRun,
                                onPartial: partialHandler
                            )
                        }

                        return ProseCandidateRunResult(
                            candidateID: input.candidateID,
                            request: input.request,
                            text: result.text,
                            usage: result.usage,
                            errorMessage: nil,
                            cancelled: false,
                            elapsedSeconds: Date().timeIntervalSince(started)
                        )
                    } catch is CancellationError {
                        return ProseCandidateRunResult(
                            candidateID: input.candidateID,
                            request: input.request,
                            text: nil,
                            usage: nil,
                            errorMessage: nil,
                            cancelled: true,
                            elapsedSeconds: Date().timeIntervalSince(started)
                        )
                    } catch {
                        return ProseCandidateRunResult(
                            candidateID: input.candidateID,
                            request: input.request,
                            text: nil,
                            usage: nil,
                            errorMessage: error.localizedDescription,
                            cancelled: false,
                            elapsedSeconds: Date().timeIntervalSince(started)
                        )
                    }
                }
            }

            for await outcome in group {
                completed += 1
                applyProseCandidateRunResult(outcome, reviewID: reviewID)
                generationStatus = "Generating \(completed)/\(total)..."
                if let existingToastID = toastID {
                    toastID = showTaskNotification(
                        "Generating candidates (\(completed)/\(total))…",
                        style: .progress,
                        updating: existingToastID,
                        autoDismiss: false
                    )
                }
            }
        }

        let wasCancelled = Task.isCancelled
        if wasCancelled {
            generationStatus = "Generation cancelled."
            markRunningProseCandidatesCancelled(reviewID: reviewID)
            finishTaskCancelledToast(toastID, "Generation cancelled.")
        }

        if var review = proseGenerationReview, review.id == reviewID {
            review.isRunning = false
            proseGenerationReview = review

            if wasCancelled {
                if review.successCount > 0 {
                    let label = review.successCount == 1 ? "candidate" : "candidates"
                    generationStatus = "Generation cancelled. \(review.successCount) \(label) completed."
                }
            } else if review.successCount > 0 {
                let label = review.successCount == 1 ? "candidate" : "candidates"
                generationStatus = "Review \(review.successCount) \(label) and accept one."
                if !wasCancelled {
                    finishTaskSuccessToast(toastID, "Generation completed. \(review.successCount) \(label) ready.")
                }
            } else {
                generationStatus = "No candidate was generated."
                if !wasCancelled {
                    finishTaskWarningToast(toastID, "Generation completed with no candidates.")
                }
            }
        } else if !wasCancelled {
            generationStatus = "Generation finished."
            finishTaskSuccessToast(toastID, "Generation completed.")
        }

        if !wasCancelled {
            saveProject(debounced: true)
        }
    }

    private func generateFromBeatInline(
        beat: String,
        scene: Scene,
        modelOverride: String?
    ) async {
        let request = makeProseGenerationRequest(
            beat: beat,
            scene: scene,
            modelOverride: modelOverride
        ).request
        rememberBeatInputHistory(beat, for: scene.id)

        proseGenerationReview = nil
        proseGenerationSessionContext = nil
        isGenerating = true
        generationStatus = shouldUseStreaming ? "Streaming..." : "Generating..."
        proseLiveUsage = normalizedTokenUsage(from: nil, request: request, response: "")
        let toastID = startTaskProgressToast("Generating text…")

        defer {
            isGenerating = false
        }

        let generationBase = makeGenerationAppendBase(for: scene.id)

        let generationPartialHandler: (@MainActor (String) -> Void)?
        if shouldUseStreaming {
            generationPartialHandler = { [weak self] partial in
                guard let self, let base = generationBase else { return }
                self.setGeneratedTextPreview(sceneID: scene.id, base: base, generated: partial)
                self.generationStatus = "Streaming..."
                self.proseLiveUsage = self.normalizedTokenUsage(from: nil, request: request, response: partial)
            }
        } else {
            generationPartialHandler = nil
        }

        do {
            let result = try await generateTextResult(
                request,
                onPartial: generationPartialHandler
            )
            let text = result.text

            if shouldUseStreaming, let base = generationBase {
                let normalized = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                setGeneratedTextPreview(sceneID: scene.id, base: base, generated: normalized)
            } else {
                appendGeneratedText(text)
            }

            proseLiveUsage = normalizedTokenUsage(from: result.usage, request: request, response: text)
            generationStatus = "Generated \(text.count) characters."
            beatInput = ""
            saveProject()
            finishTaskSuccessToast(toastID, "Generation completed.")
        } catch is CancellationError {
            generationStatus = "Generation cancelled."
            saveProject()
            finishTaskCancelledToast(toastID, "Generation cancelled.")
        } catch {
            proseLiveUsage = nil
            lastError = error.localizedDescription
            generationStatus = "Generation failed."
            finishTaskErrorToast(toastID, "Generation failed.")
        }
    }

    private func applyProseCandidateRunResult(_ outcome: ProseCandidateRunResult, reviewID: UUID) {
        guard var review = proseGenerationReview, review.id == reviewID else { return }
        guard let index = review.candidates.firstIndex(where: { $0.id == outcome.candidateID }) else { return }

        let normalizedText = outcome.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if outcome.cancelled {
            review.candidates[index].status = .cancelled
            review.candidates[index].errorMessage = nil
            review.candidates[index].text = ""
            review.candidates[index].usage = nil
        } else if normalizedText.isEmpty {
            review.candidates[index].status = .failed
            review.candidates[index].errorMessage = outcome.errorMessage ?? "No text returned."
            review.candidates[index].text = ""
            review.candidates[index].usage = nil
        } else {
            let usage = normalizedTokenUsage(
                from: outcome.usage,
                request: outcome.request,
                response: normalizedText
            )
            review.candidates[index].status = .completed
            review.candidates[index].errorMessage = nil
            review.candidates[index].text = normalizedText
            review.candidates[index].usage = usage
            proseLiveUsage = usage
        }
        review.candidates[index].elapsedSeconds = max(0, outcome.elapsedSeconds)
        review.isRunning = review.candidates.contains { !$0.status.isTerminal }
        proseGenerationReview = review
    }

    private func updateProseCandidatePartial(
        candidateID: UUID,
        partial: String,
        request: TextGenerationRequest,
        reviewID: UUID,
        startedAt: Date
    ) {
        guard var review = proseGenerationReview, review.id == reviewID else { return }
        guard let index = review.candidates.firstIndex(where: { $0.id == candidateID }) else { return }

        review.candidates[index].status = .running
        review.candidates[index].text = partial
        let usage = normalizedTokenUsage(from: nil, request: request, response: partial)
        review.candidates[index].usage = usage
        review.candidates[index].errorMessage = nil
        review.candidates[index].elapsedSeconds = max(0, Date().timeIntervalSince(startedAt))
        proseLiveUsage = usage
        proseGenerationReview = review
    }

    private func markRunningProseCandidatesCancelled(reviewID: UUID) {
        guard var review = proseGenerationReview, review.id == reviewID else { return }
        for index in review.candidates.indices where review.candidates[index].status == .running || review.candidates[index].status == .queued {
            review.candidates[index].status = .cancelled
            review.candidates[index].errorMessage = nil
            review.candidates[index].text = ""
            review.candidates[index].usage = nil
        }
        review.isRunning = false
        proseGenerationReview = review
    }

    private func resolveGenerationModelSelection(modelsOverride: [String]?) -> [String] {
        if let modelsOverride {
            let normalized = normalizedModelSelection(modelsOverride)
            if !normalized.isEmpty {
                return normalized
            }
        }

        let selected = selectedGenerationModels
        if !selected.isEmpty {
            return selected
        }

        let fallback = project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? [] : [fallback]
    }

    private func resolvedPrimaryModel() -> String {
        let configured = project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if availableRemoteModels.isEmpty {
            return configured
        }

        if availableRemoteModels.contains(configured) {
            return configured
        }

        return selectedGenerationModels.first ?? availableRemoteModels.first ?? configured
    }

    private func makeProseGenerationRequest(
        beat: String,
        scene: Scene,
        modelOverride: String? = nil
    ) -> PromptRequestBuildResult {
        let activePrompt = activeProsePrompt ?? defaultPromptTemplate(for: .prose)
        let sceneContextSections = buildCompendiumContextSections(for: scene.id, mentionSourceText: beat)
        let sceneContext = String(scene.content.suffix(Self.proseSceneTailChars))
        let sceneSummary = scene.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        let promptResult = renderPromptTemplate(
            template: activePrompt.userTemplate,
            fallbackTemplate: fallbackUserTemplate(for: activePrompt, category: .prose),
            beat: beat,
            selection: "",
            sceneID: scene.id,
            sceneExcerpt: sceneContext,
            sceneFullText: scene.content,
            sceneTitle: displaySceneTitle(scene),
            chapterTitle: chapterTitle(forSceneID: scene.id),
            contextSections: sceneContextSections,
            conversation: "",
            conversationTurns: [],
            summaryScope: "",
            source: sceneContext,
            extraVariables: [
                "scene_summary": sceneSummary
            ]
        )

        let systemPrompt = activePrompt.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? project.settings.defaultSystemPrompt
            : activePrompt.systemTemplate

        let fallbackModel = resolvedPrimaryModel()
        let selectedModel = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? modelOverride!.trimmingCharacters(in: .whitespacesAndNewlines)
            : fallbackModel

        return PromptRequestBuildResult(
            request: TextGenerationRequest(
                systemPrompt: systemPrompt,
                userPrompt: promptResult.renderedText,
                model: selectedModel,
                temperature: project.settings.temperature,
                maxTokens: project.settings.maxTokens
            ),
            renderWarnings: promptResult.warnings
        )
    }

    private func makeRewriteRequest(
        selectedText: String,
        scene: Scene,
        beatOverride: String? = nil
    ) -> PromptRequestBuildResult {
        let prompt = activeRewritePrompt ?? defaultPromptTemplate(for: .rewrite)
        let rewriteBeat = (beatOverride ?? beatInput).trimmingCharacters(in: .whitespacesAndNewlines)
        let sceneContextSections = buildCompendiumContextSections(for: scene.id, mentionSourceText: rewriteBeat)
        let sceneContext = String(scene.content.suffix(Self.rewriteSceneContextChars))
        let localSelectionContext = selectionLocalContext(
            selectedText: selectedText,
            in: scene.content
        )

        let promptResult = renderPromptTemplate(
            template: prompt.userTemplate,
            fallbackTemplate: fallbackUserTemplate(for: prompt, category: .rewrite),
            beat: rewriteBeat,
            selection: selectedText,
            sceneID: scene.id,
            sceneExcerpt: sceneContext,
            sceneFullText: scene.content,
            sceneTitle: displaySceneTitle(scene),
            chapterTitle: chapterTitle(forSceneID: scene.id),
            contextSections: sceneContextSections,
            conversation: "",
            conversationTurns: [],
            summaryScope: "",
            source: selectedText,
            extraVariables: [
                "selection_context": localSelectionContext
            ]
        )

        let systemPrompt = prompt.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? project.settings.defaultSystemPrompt
            : prompt.systemTemplate

        return PromptRequestBuildResult(
            request: TextGenerationRequest(
                systemPrompt: systemPrompt,
                userPrompt: promptResult.renderedText,
                model: resolvedPrimaryModel(),
                temperature: project.settings.temperature,
                maxTokens: project.settings.maxTokens
            ),
            renderWarnings: promptResult.warnings
        )
    }

    private func selectionLocalContext(
        selectedText: String,
        in sceneText: String,
        surroundingCharacters: Int = 700
    ) -> String {
        let normalizedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedScene = sceneText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSelection.isEmpty, !normalizedScene.isEmpty else {
            return ""
        }

        let sceneNSString = sceneText as NSString
        let selectionRange = sceneNSString.range(
            of: normalizedSelection,
            options: [.caseInsensitive, .diacriticInsensitive]
        )

        if selectionRange.location == NSNotFound {
            let fallbackLength = min(max(0, surroundingCharacters * 2), sceneNSString.length)
            guard fallbackLength > 0 else { return "" }
            let fallbackLocation = max(0, sceneNSString.length - fallbackLength)
            return sceneNSString.substring(
                with: NSRange(location: fallbackLocation, length: fallbackLength)
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let beforeLocation = max(0, selectionRange.location - surroundingCharacters)
        let beforeLength = selectionRange.location - beforeLocation
        let afterLocation = selectionRange.location + selectionRange.length
        let afterLength = max(0, min(surroundingCharacters, sceneNSString.length - afterLocation))

        let beforeText = beforeLength > 0
            ? sceneNSString.substring(with: NSRange(location: beforeLocation, length: beforeLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        let selectedSceneText = sceneNSString.substring(with: selectionRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let afterText = afterLength > 0
            ? sceneNSString.substring(with: NSRange(location: afterLocation, length: afterLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        var sections: [String] = []
        if !beforeText.isEmpty {
            sections.append("Before:\n\(beforeText)")
        }
        sections.append("Selection:\n\(selectedSceneText)")
        if !afterText.isEmpty {
            sections.append("After:\n\(afterText)")
        }

        return sections.joined(separator: "\n\n")
    }

    private func makeSummaryRequest(scene: Scene) -> PromptRequestBuildResult {
        let prompt = activeSummaryPrompt ?? defaultPromptTemplate(for: .summary)
        let sceneContextSections = buildCompendiumContextSections(for: scene.id)
        let sceneContext = String(scene.content.suffix(Self.summarySourceChars))
        let scopeContext = """
        Scope: scene summary
        \(sceneContextSections.combined)
        """

        let promptResult = renderPromptTemplate(
            template: prompt.userTemplate,
            fallbackTemplate: fallbackUserTemplate(for: prompt, category: .summary),
            beat: "",
            selection: "",
            sceneID: scene.id,
            sceneExcerpt: sceneContext,
            sceneFullText: scene.content,
            sceneTitle: displaySceneTitle(scene),
            chapterTitle: chapterTitle(forSceneID: scene.id),
            contextSections: SceneContextSections(
                combined: scopeContext,
                compendium: sceneContextSections.compendium,
                sceneSummaries: sceneContextSections.sceneSummaries,
                chapterSummaries: sceneContextSections.chapterSummaries
            ),
            conversation: "",
            conversationTurns: [],
            summaryScope: "scene",
            source: sceneContext
        )

        let systemPrompt = prompt.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? project.settings.defaultSystemPrompt
            : prompt.systemTemplate

        return PromptRequestBuildResult(
            request: TextGenerationRequest(
                systemPrompt: systemPrompt,
                userPrompt: promptResult.renderedText,
                model: resolvedPrimaryModel(),
                temperature: project.settings.temperature,
                maxTokens: project.settings.maxTokens
            ),
            renderWarnings: promptResult.warnings
        )
    }

    private func makeChapterSummaryRequest(chapter: Chapter) -> PromptRequestBuildResult {
        let prompt = activeSummaryPrompt ?? defaultPromptTemplate(for: .summary)
        let sceneSummaryContext = buildChapterSceneSummaryContext(chapter: chapter)
        let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let chapterContext = """
        Scope: chapter summary from scene summaries
        Chapter: \(chapterTitle.isEmpty ? "Untitled Chapter" : chapterTitle)
        Scene count: \(chapter.scenes.count)
        """

        let promptResult = renderPromptTemplate(
            template: prompt.userTemplate,
            fallbackTemplate: fallbackUserTemplate(for: prompt, category: .summary),
            beat: "",
            selection: "",
            sceneID: nil,
            chapterID: chapter.id,
            sceneExcerpt: sceneSummaryContext,
            sceneFullText: sceneSummaryContext,
            sceneTitle: "Chapter Summary Input",
            chapterTitle: chapterTitle.isEmpty ? "Untitled Chapter" : chapterTitle,
            contextSections: SceneContextSections(
                combined: chapterContext,
                compendium: "",
                sceneSummaries: sceneSummaryContext,
                chapterSummaries: ""
            ),
            conversation: "",
            conversationTurns: [],
            summaryScope: "chapter",
            source: sceneSummaryContext
        )

        let systemPrompt = prompt.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? project.settings.defaultSystemPrompt
            : prompt.systemTemplate

        return PromptRequestBuildResult(
            request: TextGenerationRequest(
                systemPrompt: systemPrompt,
                userPrompt: promptResult.renderedText,
                model: resolvedPrimaryModel(),
                temperature: project.settings.temperature,
                maxTokens: project.settings.maxTokens
            ),
            renderWarnings: promptResult.warnings
        )
    }

    private func rememberBeatInputHistory(_ value: String, for sceneID: UUID?) {
        rememberInputHistoryEntry(
            value,
            ownerID: sceneID,
            storage: \.beatInputHistoryByScene
        )
    }

    private func rememberWorkshopInputHistory(_ value: String, for sessionID: UUID?) {
        rememberInputHistoryEntry(
            value,
            ownerID: sessionID,
            storage: \.workshopInputHistoryBySession
        )
    }

    private func rememberInputHistoryEntry(
        _ value: String,
        ownerID: UUID?,
        storage: WritableKeyPath<StoryProject, [String: [String]]>
    ) {
        guard let ownerID else { return }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let key = ownerID.uuidString
        var history = project[keyPath: storage][key] ?? []
        history.removeAll { $0 == normalized }
        history.insert(normalized, at: 0)
        project[keyPath: storage][key] = normalizedHistoryEntries(history)
    }

    private func normalizedHistoryEntries(_ values: [String]) -> [String] {
        var output: [String] = []
        var seen = Set<String>()

        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }

            output.append(normalized)
            if output.count >= 30 {
                break
            }
        }

        return output
    }

    private func applyCheckpointRestore(
        _ checkpointProject: StoryProject,
        options: CheckpointRestoreOptions
    ) {
        var merged = project

        applyCheckpointContentRestore(from: checkpointProject, into: &merged, options: options)
        applyCheckpointProjectMetadataRestore(from: checkpointProject, into: &merged, options: options)
        applyCheckpointCompendiumRestore(from: checkpointProject, into: &merged, options: options)
        applyCheckpointTemplateRestore(from: checkpointProject, into: &merged, options: options)
        applyCheckpointSettingsRestore(from: checkpointProject, into: &merged, options: options)
        applyCheckpointWorkshopRestore(from: checkpointProject, into: &merged, options: options)
        applyCheckpointInputHistoryRestore(from: checkpointProject, into: &merged, options: options)
        applyCheckpointSceneContextRestore(from: checkpointProject, into: &merged, options: options)

        merged.updatedAt = .now
        project = merged

        ensureProjectBaseline()
        ensureValidSelections()
        refreshGlobalSearchResults()
        sceneRichTextRefreshID = UUID()
        saveProject(forceWrite: true)
    }

    private func applyCheckpointContentRestore(
        from checkpointProject: StoryProject,
        into merged: inout StoryProject,
        options: CheckpointRestoreOptions
    ) {
        guard options.includeText || options.includeSummaries || options.includeNotes else { return }
        mergeChapterAndSceneContent(
            from: checkpointProject,
            into: &merged,
            options: options
        )
    }

    private func applyCheckpointProjectMetadataRestore(
        from checkpointProject: StoryProject,
        into merged: inout StoryProject,
        options: CheckpointRestoreOptions
    ) {
        if options.includeText {
            merged.title = checkpointProject.title
            merged.metadata = checkpointProject.metadata
        }
        if options.includeNotes {
            merged.notes = checkpointProject.notes
        }
    }

    private func applyCheckpointCompendiumRestore(
        from checkpointProject: StoryProject,
        into merged: inout StoryProject,
        options: CheckpointRestoreOptions
    ) {
        guard options.includeCompendium else { return }
        merged.compendium = mergeIdentifiedCollection(
            current: merged.compendium,
            source: checkpointProject.compendium,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
    }

    private func applyCheckpointTemplateRestore(
        from checkpointProject: StoryProject,
        into merged: inout StoryProject,
        options: CheckpointRestoreOptions
    ) {
        guard options.includeTemplates else { return }
        merged.prompts = mergeIdentifiedCollection(
            current: merged.prompts,
            source: checkpointProject.prompts,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
        let availablePromptIDs = Set(merged.prompts.map(\.id))
        merged.selectedProsePromptID = resolvedSelectionID(
            current: merged.selectedProsePromptID,
            checkpoint: checkpointProject.selectedProsePromptID,
            validIDs: availablePromptIDs
        )
        merged.selectedRewritePromptID = resolvedSelectionID(
            current: merged.selectedRewritePromptID,
            checkpoint: checkpointProject.selectedRewritePromptID,
            validIDs: availablePromptIDs
        )
        merged.selectedSummaryPromptID = resolvedSelectionID(
            current: merged.selectedSummaryPromptID,
            checkpoint: checkpointProject.selectedSummaryPromptID,
            validIDs: availablePromptIDs
        )
        merged.selectedWorkshopPromptID = resolvedSelectionID(
            current: merged.selectedWorkshopPromptID,
            checkpoint: checkpointProject.selectedWorkshopPromptID,
            validIDs: availablePromptIDs
        )
    }

    private func applyCheckpointSettingsRestore(
        from checkpointProject: StoryProject,
        into merged: inout StoryProject,
        options: CheckpointRestoreOptions
    ) {
        guard options.includeSettings else { return }
        merged.settings = checkpointProject.settings
        merged.editorAppearance = checkpointProject.editorAppearance
        merged.autosaveEnabled = checkpointProject.autosaveEnabled
    }

    private func applyCheckpointWorkshopRestore(
        from checkpointProject: StoryProject,
        into merged: inout StoryProject,
        options: CheckpointRestoreOptions
    ) {
        guard options.includeWorkshop else { return }
        merged.workshopSessions = mergeIdentifiedCollection(
            current: merged.workshopSessions,
            source: checkpointProject.workshopSessions,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
        let availableSessionIDs = Set(merged.workshopSessions.map(\.id))
        merged.selectedWorkshopSessionID = resolvedSelectionID(
            current: merged.selectedWorkshopSessionID,
            checkpoint: checkpointProject.selectedWorkshopSessionID,
            validIDs: availableSessionIDs
        )
        merged.rollingWorkshopMemoryBySession = mergeDictionaryEntries(
            current: merged.rollingWorkshopMemoryBySession,
            source: checkpointProject.rollingWorkshopMemoryBySession,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
        selectedWorkshopSessionID = merged.selectedWorkshopSessionID
    }

    private func applyCheckpointInputHistoryRestore(
        from checkpointProject: StoryProject,
        into merged: inout StoryProject,
        options: CheckpointRestoreOptions
    ) {
        guard options.includeInputHistory else { return }
        merged.workshopInputHistoryBySession = mergeDictionaryEntries(
            current: merged.workshopInputHistoryBySession,
            source: checkpointProject.workshopInputHistoryBySession,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
        merged.beatInputHistoryByScene = mergeDictionaryEntries(
            current: merged.beatInputHistoryByScene,
            source: checkpointProject.beatInputHistoryByScene,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
    }

    private func applyCheckpointSceneContextRestore(
        from checkpointProject: StoryProject,
        into merged: inout StoryProject,
        options: CheckpointRestoreOptions
    ) {
        guard options.includeSceneContext else { return }
        merged.sceneContextCompendiumSelection = mergeDictionaryEntries(
            current: merged.sceneContextCompendiumSelection,
            source: checkpointProject.sceneContextCompendiumSelection,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
        merged.sceneContextSceneSummarySelection = mergeDictionaryEntries(
            current: merged.sceneContextSceneSummarySelection,
            source: checkpointProject.sceneContextSceneSummarySelection,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
        merged.sceneContextChapterSummarySelection = mergeDictionaryEntries(
            current: merged.sceneContextChapterSummarySelection,
            source: checkpointProject.sceneContextChapterSummarySelection,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
        merged.sceneNarrativeStates = mergeDictionaryEntries(
            current: merged.sceneNarrativeStates,
            source: checkpointProject.sceneNarrativeStates,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
        merged.rollingSceneMemoryByScene = mergeDictionaryEntries(
            current: merged.rollingSceneMemoryByScene,
            source: checkpointProject.rollingSceneMemoryByScene,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
        merged.rollingChapterMemoryByChapter = mergeDictionaryEntries(
            current: merged.rollingChapterMemoryByChapter,
            source: checkpointProject.rollingChapterMemoryByChapter,
            restoreDeletedEntries: options.restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
        )
    }

    private func mergeChapterAndSceneContent(
        from source: StoryProject,
        into destination: inout StoryProject,
        options: CheckpointRestoreOptions
    ) {
        let shouldApplyStructureRestore = options.includeText
            && (options.restoreDeletedEntries || options.deleteEntriesNotInCheckpoint)

        let currentChapterByID = Dictionary(uniqueKeysWithValues: destination.chapters.map { ($0.id, $0) })
        let sourceChapterByID = Dictionary(uniqueKeysWithValues: source.chapters.map { ($0.id, $0) })
        let chapterIDs = shouldApplyStructureRestore
            ? mergedIDOrder(
                currentIDs: destination.chapters.map(\.id),
                sourceIDs: source.chapters.map(\.id),
                restoreDeletedEntries: options.restoreDeletedEntries,
                deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
            )
            : destination.chapters.map(\.id)

        var mergedChapters: [Chapter] = []
        mergedChapters.reserveCapacity(chapterIDs.count)

        for chapterID in chapterIDs {
            let sourceChapter = sourceChapterByID[chapterID]
            var chapter: Chapter
            if let currentChapter = currentChapterByID[chapterID] {
                chapter = currentChapter
            } else if let sourceChapter {
                chapter = sourceChapter
            } else {
                continue
            }

            if let sourceChapter {
                if options.includeText {
                    chapter.title = sourceChapter.title
                }
                if options.includeSummaries {
                    chapter.summary = sourceChapter.summary
                }
                if options.includeNotes {
                    chapter.notes = sourceChapter.notes
                }

                let currentSceneByID = Dictionary(uniqueKeysWithValues: chapter.scenes.map { ($0.id, $0) })
                let sourceSceneByID = Dictionary(uniqueKeysWithValues: sourceChapter.scenes.map { ($0.id, $0) })
                let sceneIDs = shouldApplyStructureRestore
                    ? mergedIDOrder(
                        currentIDs: chapter.scenes.map(\.id),
                        sourceIDs: sourceChapter.scenes.map(\.id),
                        restoreDeletedEntries: options.restoreDeletedEntries,
                        deleteEntriesNotInCheckpoint: options.deleteEntriesNotInCheckpoint
                    )
                    : chapter.scenes.map(\.id)

                var mergedScenes: [Scene] = []
                mergedScenes.reserveCapacity(sceneIDs.count)

                for sceneID in sceneIDs {
                    let sourceScene = sourceSceneByID[sceneID]
                    var scene: Scene
                    if let currentScene = currentSceneByID[sceneID] {
                        scene = currentScene
                    } else if let sourceScene {
                        scene = sourceScene
                    } else {
                        continue
                    }

                    if let sourceScene {
                        if options.includeText {
                            scene.title = sourceScene.title
                            scene.content = sourceScene.content
                            scene.contentRTFData = sourceScene.contentRTFData
                        }
                        if options.includeSummaries {
                            scene.summary = sourceScene.summary
                        }
                        if options.includeNotes {
                            scene.notes = sourceScene.notes
                        }
                    }

                    mergedScenes.append(scene)
                }

                chapter.scenes = mergedScenes
            }

            mergedChapters.append(chapter)
        }

        destination.chapters = mergedChapters
    }

    private func mergedIDOrder<ID: Hashable>(
        currentIDs: [ID],
        sourceIDs: [ID],
        restoreDeletedEntries: Bool,
        deleteEntriesNotInCheckpoint: Bool
    ) -> [ID] {
        if restoreDeletedEntries && deleteEntriesNotInCheckpoint {
            return sourceIDs
        }

        var result = currentIDs
        let sourceIDSet = Set(sourceIDs)

        if deleteEntriesNotInCheckpoint {
            result.removeAll { !sourceIDSet.contains($0) }
        }

        if restoreDeletedEntries {
            var existing = Set(result)
            for sourceID in sourceIDs where !existing.contains(sourceID) {
                result.append(sourceID)
                existing.insert(sourceID)
            }
        }

        return result
    }

    private func mergeIdentifiedCollection<T: Identifiable>(
        current: [T],
        source: [T],
        restoreDeletedEntries: Bool,
        deleteEntriesNotInCheckpoint: Bool
    ) -> [T] where T.ID: Hashable {
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let sourceByID = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
        let orderedIDs = mergedIDOrder(
            currentIDs: current.map(\.id),
            sourceIDs: source.map(\.id),
            restoreDeletedEntries: restoreDeletedEntries,
            deleteEntriesNotInCheckpoint: deleteEntriesNotInCheckpoint
        )

        return orderedIDs.compactMap { id in
            sourceByID[id] ?? currentByID[id]
        }
    }

    private func mergeDictionaryEntries<Key: Hashable, Value>(
        current: [Key: Value],
        source: [Key: Value],
        restoreDeletedEntries: Bool,
        deleteEntriesNotInCheckpoint: Bool
    ) -> [Key: Value] {
        if restoreDeletedEntries && deleteEntriesNotInCheckpoint {
            return source
        }

        var merged = current
        for (key, value) in source where merged[key] != nil {
            merged[key] = value
        }

        if restoreDeletedEntries {
            for (key, value) in source where merged[key] == nil {
                merged[key] = value
            }
        }

        if deleteEntriesNotInCheckpoint {
            let sourceKeys = Set(source.keys)
            merged = merged.filter { sourceKeys.contains($0.key) }
        }

        return merged
    }

    private func resolvedSelectionID<ID: Hashable>(
        current: ID?,
        checkpoint: ID?,
        validIDs: Set<ID>
    ) -> ID? {
        if let checkpoint, validIDs.contains(checkpoint) {
            return checkpoint
        }
        if let current, validIDs.contains(current) {
            return current
        }
        return nil
    }

    // MARK: - Helpers

    private func applyLoadedProject(
        _ loadedProject: StoryProject,
        from sourceURL: URL,
        rememberAsLastOpened: Bool
    ) {
        cancelProjectTasksForSwitch()

        project = loadedProject
        currentProjectURL = sourceURL.standardizedFileURL
        isProjectOpen = true
        showingSettings = false

        workshopInput = ""
        beatInput = ""
        generationStatus = ""
        workshopStatus = ""
        isGenerating = false
        workshopIsGenerating = false
        proseLiveUsage = nil
        proseGenerationReview = nil
        proseGenerationSessionContext = nil
        workshopLiveUsage = nil
        availableRemoteModels = []
        isDiscoveringModels = false
        modelDiscoveryStatus = ""

        ensureProjectBaseline()

        selectedSceneID = project.selectedSceneID ?? project.chapters.first?.scenes.first?.id
        if let selectedSceneID,
           let location = sceneLocation(for: selectedSceneID) {
            selectedChapterID = project.chapters[location.chapterIndex].id
        } else {
            selectedChapterID = project.chapters.first?.id
        }
        selectedCompendiumID = project.compendium.first?.id
        selectedWorkshopSessionID = project.selectedWorkshopSessionID ?? project.workshopSessions.first?.id

        ensureValidSelections()

        if rememberAsLastOpened, let currentProjectURL {
            persistence.saveLastOpenedProjectURL(currentProjectURL)
            NSDocumentController.shared.noteNewRecentDocumentURL(currentProjectURL)
        }

        refreshProjectCheckpoints()

        if project.settings.provider.supportsModelDiscovery {
            scheduleModelDiscovery(immediate: true)
        }
    }

    private func setClosedProjectState(clearLastOpenedReference: Bool) {
        cancelProjectTasksForSwitch()

        project = StoryProject.starter()
        isProjectOpen = false
        currentProjectURL = nil
        showingSettings = false

        selectedChapterID = nil
        selectedSceneID = nil
        selectedCompendiumID = nil
        selectedWorkshopSessionID = nil

        workshopInput = ""
        beatInput = ""
        generationStatus = ""
        workshopStatus = ""
        isGenerating = false
        workshopIsGenerating = false
        proseLiveUsage = nil
        proseGenerationReview = nil
        proseGenerationSessionContext = nil
        workshopLiveUsage = nil
        availableRemoteModels = []
        isDiscoveringModels = false
        modelDiscoveryStatus = ""
        projectCheckpoints = []
        resetGlobalSearchState()
        syncWorkshopContextTogglesFromSelectedSession()

        if clearLastOpenedReference {
            persistence.clearLastOpenedProjectURL()
        }
    }

    private func persistOpenProjectIfNeeded() throws {
        guard isProjectOpen else { return }

        if isDocumentBacked {
            project.updatedAt = .now
            documentChangeHandler?(project)
            saveCurrentDocumentToDisk()
            return
        }

        guard let currentProjectURL else { return }

        autosaveTask?.cancel()
        project.updatedAt = .now
        self.currentProjectURL = try persistence.saveProject(project, at: currentProjectURL)
    }

    private func cancelProjectTasksForSwitch() {
        autosaveTask?.cancel()
        modelDiscoveryTask?.cancel()
        workshopRequestTask?.cancel()
        workshopRollingMemoryTask?.cancel()
        proseRequestTask?.cancel()

        autosaveTask = nil
        modelDiscoveryTask = nil
        workshopRequestTask = nil
        workshopRollingMemoryTask = nil
        proseRequestTask = nil
    }

    private func ensureProjectBaseline() {
        ensureGenerationModelSelection()
        adoptLegacyPromptIDsForBuiltIns()
        seedMissingBuiltInPrompts()
        migrateBuiltInPromptTitles()
        ensureDefaultPromptSelections()

        if project.workshopSessions.isEmpty {
            let session = Self.makeInitialWorkshopSession(name: "Chat 1")
            project.workshopSessions = [session]
            project.selectedWorkshopSessionID = session.id
        }
    }

    private func adoptLegacyPromptIDsForBuiltIns() {
        var takenPromptIDs = Set(project.prompts.map(\.id))

        for builtIn in PromptTemplate.builtInTemplates {
            guard !takenPromptIDs.contains(builtIn.id) else { continue }

            guard let legacyIndex = project.prompts.firstIndex(where: { prompt in
                prompt.category == builtIn.category
                    && normalizedPromptTitle(prompt.title) == normalizedPromptTitle(builtIn.title)
            }) else {
                continue
            }

            let previousID = project.prompts[legacyIndex].id
            project.prompts[legacyIndex].id = builtIn.id

            if project.selectedProsePromptID == previousID {
                project.selectedProsePromptID = builtIn.id
            }
            if project.selectedRewritePromptID == previousID {
                project.selectedRewritePromptID = builtIn.id
            }
            if project.selectedSummaryPromptID == previousID {
                project.selectedSummaryPromptID = builtIn.id
            }
            if project.selectedWorkshopPromptID == previousID {
                project.selectedWorkshopPromptID = builtIn.id
            }

            takenPromptIDs.remove(previousID)
            takenPromptIDs.insert(builtIn.id)

            if project.prompts[legacyIndex].userTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                project.prompts[legacyIndex].userTemplate = builtIn.userTemplate
            }

            if project.prompts[legacyIndex].systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                project.prompts[legacyIndex].systemTemplate = builtIn.systemTemplate
            }
        }
    }

    private func seedMissingBuiltInPrompts() {
        var existingIDs = Set(project.prompts.map(\.id))
        for builtIn in PromptTemplate.builtInTemplates where !existingIDs.contains(builtIn.id) {
            project.prompts.append(builtIn)
            existingIDs.insert(builtIn.id)
        }
    }

    private func migrateBuiltInPromptTitles() {
        guard let proseIndex = project.prompts.firstIndex(where: { $0.id == PromptTemplate.cinematicProseID }) else {
            return
        }

        if normalizedPromptTitle(project.prompts[proseIndex].title) == "cinematic prose" {
            project.prompts[proseIndex].title = PromptTemplate.defaultProseTemplate.title
        }
    }

    private func ensureDefaultPromptSelections() {
        let proseIDs = Set(prosePrompts.map(\.id))
        let rewriteIDs = Set(rewritePrompts.map(\.id))
        let summaryIDs = Set(summaryPrompts.map(\.id))
        let workshopIDs = Set(workshopPrompts.map(\.id))

        if project.selectedProsePromptID.map({ proseIDs.contains($0) }) != true {
            project.selectedProsePromptID = prosePrompts.first(where: { $0.id == PromptTemplate.defaultProseTemplate.id })?.id
                ?? prosePrompts.first?.id
        }

        if project.selectedRewritePromptID.map({ rewriteIDs.contains($0) }) != true {
            project.selectedRewritePromptID = rewritePrompts.first(where: { $0.id == PromptTemplate.defaultRewriteTemplate.id })?.id
                ?? rewritePrompts.first?.id
        }

        if project.selectedSummaryPromptID.map({ summaryIDs.contains($0) }) != true {
            project.selectedSummaryPromptID = summaryPrompts.first(where: { $0.id == PromptTemplate.defaultSummaryTemplate.id })?.id
                ?? summaryPrompts.first?.id
        }

        if project.selectedWorkshopPromptID.map({ workshopIDs.contains($0) }) != true {
            project.selectedWorkshopPromptID = workshopPrompts.first(where: { $0.id == PromptTemplate.defaultWorkshopTemplate.id })?.id
                ?? workshopPrompts.first?.id
        }
    }

    private func normalizedPromptTitle(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizedModelSelection(_ models: [String]) -> [String] {
        var output: [String] = []
        var seen = Set<String>()

        for model in models {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                output.append(trimmed)
            }
        }

        return output
    }

    private func ensureGenerationModelSelection() {
        let normalized = normalizedModelSelection(project.settings.generationModelSelection)
        if !normalized.isEmpty {
            project.settings.generationModelSelection = normalized
            return
        }

        let fallback = project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        project.settings.generationModelSelection = fallback.isEmpty ? [] : [fallback]
    }

    @discardableResult
    private func reconcileGenerationModels(withDiscovered discoveredModels: [String]) -> Bool {
        guard !discoveredModels.isEmpty else { return false }

        let discoveredSet = Set(discoveredModels)
        var didChange = false

        var selected = normalizedModelSelection(project.settings.generationModelSelection)
        let filteredSelection = selected.filter { discoveredSet.contains($0) }
        if filteredSelection != selected {
            selected = filteredSelection
            didChange = true
        }

        var currentModel = project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentModel != project.settings.model {
            project.settings.model = currentModel
            didChange = true
        }

        if !discoveredSet.contains(currentModel) {
            let replacement = selected.first ?? discoveredModels[0]
            if project.settings.model != replacement {
                project.settings.model = replacement
                didChange = true
            }
            currentModel = replacement
        }

        if selected.isEmpty {
            selected = [currentModel]
            didChange = true
        }

        if project.settings.generationModelSelection != selected {
            project.settings.generationModelSelection = selected
            didChange = true
        }

        return didChange
    }

    private func isBuiltInPromptModified(_ prompt: PromptTemplate, comparedTo builtIn: PromptTemplate) -> Bool {
        prompt.category != builtIn.category
            || prompt.title != builtIn.title
            || prompt.userTemplate != builtIn.userTemplate
            || prompt.systemTemplate != builtIn.systemTemplate
    }

    private func normalizedEntryTitle(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func makeUniqueImportedTitle(
        baseTitle: String,
        fallback: String,
        usedTitles: inout Set<String>
    ) -> String {
        let trimmedBase = baseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBase = trimmedBase.isEmpty ? fallback : trimmedBase

        var attempt = 0
        while true {
            let candidate: String
            if attempt == 0 {
                candidate = normalizedBase
            } else if attempt == 1 {
                candidate = "\(normalizedBase) (Imported)"
            } else {
                candidate = "\(normalizedBase) (Imported \(attempt))"
            }

            let normalizedCandidate = normalizedEntryTitle(candidate)
            if usedTitles.insert(normalizedCandidate).inserted {
                return candidate
            }

            attempt += 1
        }
    }

    private func sanitizeImportedTags(_ rawTags: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for rawTag in rawTags {
            let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = trimmed.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            output.append(trimmed)
        }

        return output
    }

    private func makeProjectPlainTextExport() -> String {
        var lines: [String] = []
        lines.append(currentProjectName)

        for chapter in project.chapters {
            let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled Chapter"
                : chapter.title
            lines.append("")
            lines.append(chapterTitle)

            for scene in chapter.scenes {
                let sceneTitle = scene.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Untitled Scene"
                    : scene.title
                lines.append("")
                lines.append(sceneTitle)
                lines.append(scene.content)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func makeProjectHTMLExport() -> String {
        var html: [String] = []
        html.append("<!doctype html>")
        html.append("<html lang=\"en\">")
        html.append("<head>")
        html.append("  <meta charset=\"utf-8\">")
        html.append("  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
        html.append("  <title>\(escapeHTML(currentProjectName))</title>")
        html.append("  <style>")
        html.append("    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 2rem auto; max-width: 980px; line-height: 1.45; padding: 0 1rem; }")
        html.append("    h1 { margin-bottom: 1.25rem; }")
        html.append("    h2 { margin-top: 2rem; margin-bottom: 0.6rem; border-bottom: 1px solid #ddd; padding-bottom: 0.25rem; }")
        html.append("    h3 { margin-top: 1.25rem; margin-bottom: 0.45rem; }")
        html.append("    article { margin-bottom: 1rem; }")
        html.append("    p { margin: 0 0 0.75rem 0; }")
        html.append("  </style>")
        html.append("</head>")
        html.append("<body>")
        html.append("  <h1>\(escapeHTML(currentProjectName))</h1>")

        for chapter in project.chapters {
            let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled Chapter"
                : chapter.title
            html.append("  <section>")
            html.append("    <h2>\(escapeHTML(chapterTitle))</h2>")

            for scene in chapter.scenes {
                let sceneTitle = scene.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Untitled Scene"
                    : scene.title
                html.append("    <article>")
                html.append("      <h3>\(escapeHTML(sceneTitle))</h3>")
                html.append(htmlParagraphs(for: scene.content, indent: "      "))
                html.append("    </article>")
            }

            html.append("  </section>")
        }

        html.append("</body>")
        html.append("</html>")

        return html.joined(separator: "\n")
    }

    private func htmlParagraphs(for rawText: String, indent: String) -> String {
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "\(indent)<p></p>"
        }

        let chunks = trimmed.components(separatedBy: "\n\n")
        return chunks.map { chunk in
            let escaped = escapeHTML(chunk).replacingOccurrences(of: "\n", with: "<br>")
            return "\(indent)<p>\(escaped)</p>"
        }.joined(separator: "\n")
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func writeUTF8(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        try data.write(to: url, options: .atomic)
    }

    private func createEPUBArchive(from packageRoot: URL, to outputURL: URL) throws {
        try runProcess(
            executablePath: "/usr/bin/zip",
            arguments: ["-X0", outputURL.path, "mimetype"],
            currentDirectoryURL: packageRoot
        )
        try runProcess(
            executablePath: "/usr/bin/zip",
            arguments: ["-Xr9D", outputURL.path, "META-INF", "OEBPS"],
            currentDirectoryURL: packageRoot
        )
    }

    private func extractEPUBArchive(from archiveURL: URL, to destinationURL: URL) throws {
        try runProcess(
            executablePath: "/usr/bin/unzip",
            arguments: ["-q", archiveURL.path, "-d", destinationURL.path]
        )
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            let details = [error, output]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            let description = details.isEmpty
                ? "Process failed with exit code \(process.terminationStatus)."
                : details
            throw NSError(
                domain: "Scene.Archive",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        }
    }

    private func makeEPUBChapterXHTML(
        chapter: Chapter,
        chapterTitle: String,
        chapterIndex: Int
    ) -> String {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<!DOCTYPE html>")
        lines.append("<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">")
        lines.append("<head>")
        lines.append("  <meta charset=\"utf-8\"/>")
        lines.append("  <title>\(escapeHTML(chapterTitle))</title>")
        lines.append("</head>")
        lines.append("<body>")
        lines.append("  <h1>\(escapeHTML(chapterTitle))</h1>")

        if chapter.scenes.isEmpty {
            lines.append("  <section>")
            lines.append("    <h2>Scene 1</h2>")
            lines.append("    <p></p>")
            lines.append("  </section>")
        } else {
            for (sceneIndex, scene) in chapter.scenes.enumerated() {
                let sceneTitle = scene.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Scene \(sceneIndex + 1)"
                    : scene.title
                lines.append("  <section id=\"scene-\(chapterIndex + 1)-\(sceneIndex + 1)\">")
                lines.append("    <h2>\(escapeHTML(sceneTitle))</h2>")
                lines.append(htmlParagraphs(for: scene.content, indent: "    "))
                lines.append("  </section>")
            }
        }

        lines.append("</body>")
        lines.append("</html>")
        return lines.joined(separator: "\n")
    }

    private func makeEPUBNavigationXHTML(chapters: [(id: String, href: String, title: String)]) -> String {
        let projectTitle = normalizedTitle(project.title, fallback: currentProjectName)

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<!DOCTYPE html>")
        lines.append("<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" xml:lang=\"en\" lang=\"en\">")
        lines.append("<head>")
        lines.append("  <meta charset=\"utf-8\"/>")
        lines.append("  <title>\(escapeHTML(projectTitle))</title>")
        lines.append("</head>")
        lines.append("<body>")
        lines.append("  <nav epub:type=\"toc\" id=\"toc\">")
        lines.append("    <h1>\(escapeHTML(projectTitle))</h1>")
        lines.append("    <ol>")
        for chapter in chapters {
            lines.append("      <li><a href=\"\(escapeHTML(chapter.href))\">\(escapeHTML(chapter.title))</a></li>")
        }
        lines.append("    </ol>")
        lines.append("  </nav>")
        lines.append("</body>")
        lines.append("</html>")
        return lines.joined(separator: "\n")
    }

    private func makeEPUBPackageOPF(chapters: [(id: String, href: String, title: String)]) -> String {
        let modifiedFormatter = ISO8601DateFormatter()
        modifiedFormatter.formatOptions = [.withInternetDateTime]
        let modified = modifiedFormatter.string(from: .now)
        let bookIdentifier = "urn:uuid:\(project.id.uuidString.lowercased())"
        let projectTitle = normalizedTitle(project.title, fallback: currentProjectName)
        let language = normalizedEPUBMetadataValue(project.metadata.language) ?? "en"

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<package xmlns=\"http://www.idpf.org/2007/opf\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" version=\"3.0\" unique-identifier=\"book-id\" xml:lang=\"\(escapeHTML(language))\">")
        lines.append("  <metadata>")
        lines.append("    <dc:identifier id=\"book-id\">\(escapeHTML(bookIdentifier))</dc:identifier>")
        lines.append("    <dc:title>\(escapeHTML(projectTitle))</dc:title>")
        lines.append("    <dc:language>\(escapeHTML(language))</dc:language>")

        if let author = normalizedEPUBMetadataValue(project.metadata.author) {
            lines.append("    <dc:creator>\(escapeHTML(author))</dc:creator>")
        }
        if let publisher = normalizedEPUBMetadataValue(project.metadata.publisher) {
            lines.append("    <dc:publisher>\(escapeHTML(publisher))</dc:publisher>")
        }
        if let rights = normalizedEPUBMetadataValue(project.metadata.rights) {
            lines.append("    <dc:rights>\(escapeHTML(rights))</dc:rights>")
        }
        if let description = normalizedEPUBMetadataValue(project.metadata.description) {
            lines.append("    <dc:description>\(escapeHTML(description))</dc:description>")
        }

        lines.append("    <meta property=\"dcterms:modified\">\(modified)</meta>")
        lines.append("  </metadata>")
        lines.append("  <manifest>")
        lines.append("    <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>")
        for chapter in chapters {
            lines.append("    <item id=\"\(escapeHTML(chapter.id))\" href=\"\(escapeHTML(chapter.href))\" media-type=\"application/xhtml+xml\"/>")
        }
        lines.append("    <item id=\"scene-project\" href=\"scene-project.json\" media-type=\"application/json\"/>")
        lines.append("  </manifest>")
        lines.append("  <spine>")
        for chapter in chapters {
            lines.append("    <itemref idref=\"\(escapeHTML(chapter.id))\"/>")
        }
        lines.append("  </spine>")
        lines.append("</package>")
        return lines.joined(separator: "\n")
    }

    private func locateEPUBRoot(in extractionRoot: URL) throws -> URL {
        let directContainer = extractionRoot
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")
        if FileManager.default.fileExists(atPath: directContainer.path) {
            return extractionRoot
        }

        if let enumerator = FileManager.default.enumerator(at: extractionRoot, includingPropertiesForKeys: nil) {
            for case let candidate as URL in enumerator {
                guard candidate.lastPathComponent == "container.xml" else { continue }
                guard candidate.deletingLastPathComponent().lastPathComponent == "META-INF" else { continue }
                return candidate.deletingLastPathComponent().deletingLastPathComponent()
            }
        }

        throw DataExchangeError.invalidEPUB("Missing META-INF/container.xml.")
    }

    private func parseEPUBPackageDescriptor(in packageRoot: URL) throws -> EPUBPackageDescriptor {
        let containerURL = packageRoot
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")
        guard let containerText = try? String(contentsOf: containerURL, encoding: .utf8) else {
            throw DataExchangeError.invalidEPUB("Cannot read container.xml.")
        }

        var rootfilePath = firstCapturedValue(
            in: containerText,
            pattern: "<rootfile\\b[^>]*full-path\\s*=\\s*['\"]([^'\"]+)['\"][^>]*/?>"
        )

        if rootfilePath == nil,
           let opfURL = firstFile(withExtension: "opf", in: packageRoot) {
            rootfilePath = opfURL.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
        }

        guard let rootfilePath else {
            throw DataExchangeError.invalidEPUB("Container does not reference OPF package.")
        }

        let opfURL = URL(fileURLWithPath: rootfilePath, relativeTo: packageRoot).standardizedFileURL
        guard let opfText = try? String(contentsOf: opfURL, encoding: .utf8) else {
            throw DataExchangeError.invalidEPUB("Cannot read OPF package at '\(rootfilePath)'.")
        }

        let title = normalizedTitle(
            normalizedEPUBMetadataValue(
                firstCapturedValue(
                    in: opfText,
                    pattern: "<dc:title\\b[^>]*>(.*?)</dc:title>"
                )
            ),
            fallback: "Imported EPUB"
        )

        let languageFromPackageTag: String?
        if let packageTag = allTagMatches(in: opfText, tagName: "package").first {
            languageFromPackageTag = parseXMLAttributes(fromTag: packageTag)["xml:lang"]
        } else {
            languageFromPackageTag = nil
        }

        let metadata = ProjectMetadata(
            author: normalizedEPUBMetadataValue(
                firstCapturedValue(
                    in: opfText,
                    pattern: "<dc:creator\\b[^>]*>(.*?)</dc:creator>"
                )
            ),
            language: normalizedEPUBMetadataValue(
                firstCapturedValue(
                    in: opfText,
                    pattern: "<dc:language\\b[^>]*>(.*?)</dc:language>"
                ) ?? languageFromPackageTag
            ),
            publisher: normalizedEPUBMetadataValue(
                firstCapturedValue(
                    in: opfText,
                    pattern: "<dc:publisher\\b[^>]*>(.*?)</dc:publisher>"
                )
            ),
            rights: normalizedEPUBMetadataValue(
                firstCapturedValue(
                    in: opfText,
                    pattern: "<dc:rights\\b[^>]*>(.*?)</dc:rights>"
                )
            ),
            description: normalizedEPUBMetadataValue(
                firstCapturedValue(
                    in: opfText,
                    pattern: "<dc:description\\b[^>]*>(.*?)</dc:description>"
                )
            )
        )

        var manifestByID: [String: EPUBManifestItem] = [:]
        for tag in allTagMatches(in: opfText, tagName: "item") {
            let attributes = parseXMLAttributes(fromTag: tag)
            guard let id = attributes["id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  let href = attributes["href"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty else {
                continue
            }
            let mediaType = attributes["media-type"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            manifestByID[id] = EPUBManifestItem(
                id: id,
                href: href,
                mediaType: mediaType,
                properties: attributes["properties"]
            )
        }

        var spineItemIDs: [String] = []
        for tag in allTagMatches(in: opfText, tagName: "itemref") {
            let attributes = parseXMLAttributes(fromTag: tag)
            if let idref = attributes["idref"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !idref.isEmpty {
                spineItemIDs.append(idref)
            }
        }

        return EPUBPackageDescriptor(
            title: title,
            metadata: metadata,
            opfURL: opfURL,
            packageBaseURL: opfURL.deletingLastPathComponent(),
            manifestByID: manifestByID,
            spineItemIDs: spineItemIDs
        )
    }

    private func loadEmbeddedProjectFromEPUB(descriptor: EPUBPackageDescriptor) throws -> StoryProject? {
        var candidateURLs: [URL] = []

        if let manifestMatch = descriptor.manifestByID.values.first(where: { item in
            item.href.lowercased().contains("scene-project.json")
        }) {
            let decodedHref = manifestMatch.href.removingPercentEncoding ?? manifestMatch.href
            let url = URL(fileURLWithPath: decodedHref, relativeTo: descriptor.packageBaseURL).standardizedFileURL
            candidateURLs.append(url)
        }

        candidateURLs.append(
            descriptor.packageBaseURL.appendingPathComponent("scene-project.json")
        )

        candidateURLs.append(contentsOf: files(named: "scene-project.json", in: descriptor.packageBaseURL))

        var seen = Set<String>()
        for url in candidateURLs {
            let standardized = url.standardizedFileURL.path
            guard seen.insert(standardized).inserted else { continue }
            guard FileManager.default.fileExists(atPath: standardized) else { continue }

            let data = try Data(contentsOf: url)
            if let envelope = try? Self.transferDecoder.decode(ProjectTransferEnvelope.self, from: data),
               envelope.type == Self.projectTransferType {
                return envelope.project
            }
        }

        return nil
    }

    private func parseEPUBChapters(descriptor: EPUBPackageDescriptor) throws -> [Chapter] {
        let documentURLs = resolveEPUBDocumentURLs(descriptor: descriptor)
        var chapters: [Chapter] = []

        for (index, documentURL) in documentURLs.enumerated() {
            guard let parsed = parseEPUBChapter(from: documentURL, fallbackIndex: index) else {
                continue
            }

            let scenes: [Scene] = parsed.scenes.enumerated().map { sceneIndex, parsedScene in
                Scene(
                    title: parsedScene.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Scene \(sceneIndex + 1)"
                        : parsedScene.title,
                    content: parsedScene.content
                )
            }

            guard !scenes.isEmpty else { continue }
            let chapterTextLength = scenes.reduce(0) { $0 + $1.content.count }
            if shouldSkipLikelyAuxiliaryEPUBDocument(
                documentURL: documentURL,
                chapterTextLength: chapterTextLength
            ) {
                continue
            }
            chapters.append(
                Chapter(
                    title: normalizedTitle(parsed.title, fallback: "Chapter \(index + 1)"),
                    scenes: scenes
                )
            )
        }

        return chapters
    }

    private func resolveEPUBDocumentURLs(descriptor: EPUBPackageDescriptor) -> [URL] {
        let preferredMediaTypes = Set([
            "application/xhtml+xml",
            "application/x-dtbook+xml",
            "text/html"
        ])

        var urls: [URL] = []
        var seen = Set<String>()

        for idref in descriptor.spineItemIDs {
            guard let item = descriptor.manifestByID[idref] else { continue }
            let mediaType = item.mediaType.lowercased()
            if !mediaType.isEmpty && !preferredMediaTypes.contains(mediaType) {
                continue
            }
            if item.properties?.localizedCaseInsensitiveContains("nav") == true {
                continue
            }

            let href = item.href.removingPercentEncoding ?? item.href
            let url = URL(fileURLWithPath: href, relativeTo: descriptor.packageBaseURL).standardizedFileURL
            if seen.insert(url.path).inserted {
                urls.append(url)
            }
        }

        if !urls.isEmpty {
            return urls
        }

        let fallback = files(withExtensions: ["xhtml", "html", "htm"], in: descriptor.packageBaseURL)
            .sorted { lhs, rhs in
                lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }

        for url in fallback where seen.insert(url.path).inserted {
            urls.append(url)
        }

        return urls
    }

    private func parseEPUBChapter(from fileURL: URL, fallbackIndex: Int) -> EPUBParsedChapter? {
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let chapterTitleFromH1 = firstCapturedValue(in: source, pattern: "<h1\\b[^>]*>(.*?)</h1>")
            .map(plainTextFromHTMLFragment(_:))
            .flatMap { $0.isEmpty ? nil : $0 }

        let chapterTitleFromTitleTag = firstCapturedValue(in: source, pattern: "<title\\b[^>]*>(.*?)</title>")
            .map(plainTextFromHTMLFragment(_:))
            .flatMap { $0.isEmpty ? nil : $0 }

        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let chapterTitle = chapterTitleFromH1
            ?? chapterTitleFromTitleTag
            ?? normalizedTitle(fallbackTitle, fallback: "Chapter \(fallbackIndex + 1)")

        let tokenPattern = "<(h[1-6]|p|li|blockquote)\\b[^>]*>(.*?)</\\1>"
        guard let tokenRegex = try? NSRegularExpression(
            pattern: tokenPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = tokenRegex.matches(in: source, options: [], range: sourceRange)

        var scenes: [EPUBSceneBuilder] = []
        var pendingParagraphs: [String] = []

        func appendParagraph(_ paragraph: String) {
            if scenes.isEmpty {
                pendingParagraphs.append(paragraph)
            } else {
                scenes[scenes.count - 1].paragraphs.append(paragraph)
            }
        }

        func flushPendingParagraphsIntoScenes() {
            guard !pendingParagraphs.isEmpty else { return }
            if scenes.isEmpty {
                scenes.append(EPUBSceneBuilder(title: "Scene 1", paragraphs: pendingParagraphs))
            } else {
                scenes[scenes.count - 1].paragraphs.append(contentsOf: pendingParagraphs)
            }
            pendingParagraphs = []
        }

        for match in matches {
            guard let typeRange = Range(match.range(at: 1), in: source),
                  let valueRange = Range(match.range(at: 2), in: source) else {
                continue
            }

            let elementType = source[typeRange].lowercased()
            let textValue = plainTextFromHTMLFragment(String(source[valueRange]))
            guard !textValue.isEmpty else { continue }

            switch elementType {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let headingLevel = Int(elementType.dropFirst()) ?? 1
                if shouldTreatEPUBHeadingAsSceneTitle(textValue, headingLevel: headingLevel) {
                    flushPendingParagraphsIntoScenes()
                    scenes.append(EPUBSceneBuilder(title: textValue, paragraphs: []))
                } else {
                    appendParagraph(textValue)
                }

            case "p", "li", "blockquote":
                appendParagraph(textValue)

            default:
                break
            }
        }

        flushPendingParagraphsIntoScenes()

        if scenes.isEmpty {
            let bodyText = extractEPUBBodyText(from: source)
            let paragraphs = splitIntoParagraphs(bodyText)
            if !paragraphs.isEmpty {
                scenes = [EPUBSceneBuilder(title: "Scene 1", paragraphs: paragraphs)]
            }
        }

        let parsedScenes: [EPUBParsedScene] = scenes.enumerated().map { index, scene in
            let title = scene.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Scene \(index + 1)"
                : scene.title
            let content = scene.paragraphs.joined(separator: "\n\n")
            return EPUBParsedScene(title: title, content: content)
        }.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.title.isEmpty }

        guard !parsedScenes.isEmpty else { return nil }
        return EPUBParsedChapter(title: chapterTitle, scenes: parsedScenes)
    }

    private func shouldTreatEPUBHeadingAsSceneTitle(_ text: String, headingLevel: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let wordCount = trimmed
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
        let characterCount = trimmed.count
        let hasTerminalSentencePunctuation = trimmed.range(
            of: #"[.!?…]["'”’)]?$"#,
            options: .regularExpression
        ) != nil

        // Long heading-tag text is usually body prose in malformed EPUBs.
        if characterCount >= 160 || wordCount >= 22 {
            return false
        }

        // H1 is often repurposed by generated EPUBs; require stricter heading shape.
        if headingLevel == 1 {
            return characterCount <= 90
                && wordCount <= 12
                && !hasTerminalSentencePunctuation
        }

        // For H2-H6, allow slightly longer structural headings.
        return characterCount <= 140
            && wordCount <= 18
            && !hasTerminalSentencePunctuation
    }

    private func shouldSkipLikelyAuxiliaryEPUBDocument(
        documentURL: URL,
        chapterTextLength: Int
    ) -> Bool {
        let fullPath = documentURL.path.lowercased()
        let fileName = documentURL.deletingPathExtension().lastPathComponent.lowercased()

        let hasNonBodyMarker = Self.epubNonBodyNameMarkers.contains { marker in
            fileName.contains(marker) || fullPath.contains("/\(marker)")
        }
        let hasNotesMarker = Self.epubNotesNameMarkers.contains { marker in
            fileName.contains(marker) || fullPath.contains("/\(marker)")
        }

        guard hasNonBodyMarker || hasNotesMarker else {
            return false
        }

        // Keep auxiliary docs only when they carry substantial textual content.
        return chapterTextLength < Self.epubAuxDocumentKeepThresholdChars
    }

    private func extractEPUBBodyText(from source: String) -> String {
        if let bodyFragment = firstCapturedValue(
            in: source,
            pattern: "<body\\b[^>]*>(.*?)</body>"
        ) {
            return plainTextFromHTMLFragment(bodyFragment)
        }
        return plainTextFromHTMLFragment(source)
    }

    private func splitIntoParagraphs(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        return normalized
            .components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
            .filter { !$0.isEmpty }
    }

    private func plainTextFromHTMLFragment(_ fragment: String) -> String {
        let wrapped = "<!doctype html><html><body>\(fragment)</body></html>"
        if let data = wrapped.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
               ],
               documentAttributes: nil
           ) {
            return attributed.string
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: [.caseInsensitive]) {
            let range = NSRange(fragment.startIndex..<fragment.endIndex, in: fragment)
            let stripped = tagRegex.stringByReplacingMatches(in: fragment, options: [], range: range, withTemplate: " ")
            return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return fragment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseXMLAttributes(fromTag tag: String) -> [String: String] {
        let attributePattern = "([A-Za-z_:][A-Za-z0-9_:\\.-]*)\\s*=\\s*['\"]([^'\"]*)['\"]"
        guard let regex = try? NSRegularExpression(pattern: attributePattern, options: []) else {
            return [:]
        }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        let matches = regex.matches(in: tag, options: [], range: range)
        var output: [String: String] = [:]
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 2), in: tag) else {
                continue
            }
            output[String(tag[keyRange]).lowercased()] = String(tag[valueRange])
        }
        return output
    }

    private func allTagMatches(in source: String, tagName: String) -> [String] {
        let pattern = "<\(tagName)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, options: [], range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: source) else { return nil }
            return String(source[matchRange])
        }
    }

    private func firstCapturedValue(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[captureRange])
    }

    private func firstFile(withExtension pathExtension: String, in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == pathExtension.lowercased() {
            return fileURL
        }
        return nil
    }

    private func files(named filename: String, in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        var matches: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent.caseInsensitiveCompare(filename) == .orderedSame {
            matches.append(fileURL)
        }
        return matches
    }

    private func files(withExtensions extensions: [String], in root: URL) -> [URL] {
        let allowed = Set(extensions.map { $0.lowercased() })
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        var matches: [URL] = []
        for case let fileURL as URL in enumerator where allowed.contains(fileURL.pathExtension.lowercased()) {
            matches.append(fileURL)
        }
        return matches
    }

    private func normalizedEPUBMetadataValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let stripped = plainTextFromHTMLFragment(value)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedTitle(_ title: String?, fallback: String) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func makeInitialWorkshopSession(name: String) -> WorkshopSession {
        WorkshopSession(
            name: name,
            messages: [
                WorkshopMessage(
                    role: .assistant,
                    content: "I’m ready to workshop your story. Ask for brainstorming, continuity checks, line edits, or rewrite options."
                )
            ]
        )
    }

    private func syncWorkshopContextTogglesFromSelectedSession() {
        guard isProjectOpen, let session = selectedWorkshopSession else {
            workshopUseSceneContext = true
            workshopUseCompendiumContext = true
            return
        }

        workshopUseSceneContext = session.useSceneContext
        workshopUseCompendiumContext = session.useCompendiumContext
    }

    private func persistWorkshopContextTogglesForSelectedSession() {
        guard isProjectOpen,
              let sessionID = selectedWorkshopSessionID,
              let index = workshopSessionIndex(for: sessionID) else {
            return
        }

        var didMutateSession = false

        if project.workshopSessions[index].useSceneContext != workshopUseSceneContext {
            project.workshopSessions[index].useSceneContext = workshopUseSceneContext
            didMutateSession = true
        }

        if project.workshopSessions[index].useCompendiumContext != workshopUseCompendiumContext {
            project.workshopSessions[index].useCompendiumContext = workshopUseCompendiumContext
            didMutateSession = true
        }

        guard didMutateSession else { return }
        project.workshopSessions[index].updatedAt = .now
        saveProject(debounced: true)
    }

    private func updateWorkshopRollingMemory(
        sessionID: UUID,
        summary: String,
        summarizedMessageCount: Int
    ) {
        let key = sessionID.uuidString
        let normalizedSummary = normalizedRollingMemorySummary(
            summary,
            maxChars: Self.rollingWorkshopMemoryMaxChars
        )

        guard let sessionIndex = workshopSessionIndex(for: sessionID) else {
            project.rollingWorkshopMemoryBySession.removeValue(forKey: key)
            return
        }

        guard !normalizedSummary.isEmpty else {
            project.rollingWorkshopMemoryBySession.removeValue(forKey: key)
            saveProject(debounced: true)
            return
        }

        let clampedCount = min(
            max(0, summarizedMessageCount),
            project.workshopSessions[sessionIndex].messages.count
        )
        project.rollingWorkshopMemoryBySession[key] = RollingWorkshopMemory(
            summary: normalizedSummary,
            summarizedMessageCount: clampedCount,
            updatedAt: .now
        )
        saveProject(debounced: true)
    }

    private func updateRollingSceneMemory(
        sceneID: UUID,
        summary: String,
        sourceContent: String
    ) {
        let normalizedSummary = normalizedRollingMemorySummary(
            summary,
            maxChars: Self.rollingSceneMemoryMaxChars
        )
        let key = sceneID.uuidString
        guard !normalizedSummary.isEmpty else {
            project.rollingSceneMemoryByScene.removeValue(forKey: key)
            return
        }

        project.rollingSceneMemoryByScene[key] = RollingSceneMemory(
            summary: normalizedSummary,
            sourceContentHash: stableContentHash(sourceContent),
            updatedAt: .now
        )
    }

    private func updateRollingChapterMemory(
        chapterID: UUID,
        summary: String
    ) {
        let normalizedSummary = normalizedRollingMemorySummary(
            summary,
            maxChars: Self.rollingChapterMemoryMaxChars
        )
        let key = chapterID.uuidString
        guard let chapter = chapter(for: chapterID) else {
            project.rollingChapterMemoryByChapter.removeValue(forKey: key)
            return
        }
        guard !normalizedSummary.isEmpty else {
            project.rollingChapterMemoryByChapter.removeValue(forKey: key)
            return
        }

        project.rollingChapterMemoryByChapter[key] = RollingChapterMemory(
            summary: normalizedSummary,
            sourceFingerprint: chapterSourceFingerprint(chapter: chapter),
            updatedAt: .now
        )
    }

    private func scheduleWorkshopRollingMemoryRefresh(for sessionID: UUID) {
        workshopRollingMemoryTask?.cancel()
        workshopRollingMemoryTask = Task { [weak self] in
            await self?.refreshWorkshopRollingMemoryIfNeeded(sessionID: sessionID)
        }
    }

    private func refreshWorkshopRollingMemoryIfNeeded(sessionID: UUID) async {
        guard !Task.isCancelled else { return }
        guard let sessionIndex = workshopSessionIndex(for: sessionID) else { return }

        let session = project.workshopSessions[sessionIndex]
        let messages = session.messages.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !messages.isEmpty else { return }

        let key = sessionID.uuidString
        let existingMemory = project.rollingWorkshopMemoryBySession[key]
        let alreadySummarized = min(
            max(0, existingMemory?.summarizedMessageCount ?? 0),
            messages.count
        )
        guard messages.count > alreadySummarized else { return }

        let deltaMessages = Array(messages.dropFirst(alreadySummarized))
        guard deltaMessages.count >= Self.rollingWorkshopMemoryMinDeltaMessages else { return }
        let deltaWindow = Array(deltaMessages.suffix(Self.rollingWorkshopMemoryDeltaWindow))

        let systemPrompt = """
        You maintain concise long-lived memory for a fiction workshop chat.

        Output rules:
        - Return plain prose bullets or short paragraphs only.
        - Keep stable facts, decisions, constraints, unresolved questions, and user preferences.
        - Remove repetition and low-value chatter.
        - Do not invent facts not present in input.
        """

        let existingSummary = existingMemory?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sessionTitle = displayWorkshopSessionTitle(session)
        let transcript = deltaWindow
            .map { message in
                let role = message.role == .user ? "User" : "Assistant"
                return "\(role): \(message.content)"
            }
            .joined(separator: "\n\n")

        let userPrompt = """
        CHAT: \(sessionTitle)

        EXISTING_MEMORY:
        <<<
        \(existingSummary)
        >>>

        NEW_TURNS:
        <<<
        \(transcript)
        >>>

        TASK:
        Merge EXISTING_MEMORY with NEW_TURNS into an updated memory. Keep it compact and high-signal.
        """

        let request = TextGenerationRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: resolvedPrimaryModel(),
            temperature: min(project.settings.temperature, 0.3),
            maxTokens: min(project.settings.maxTokens, 900)
        )
        let toastID = startTaskProgressToast("Updating workshop memory…")

        do {
            let result = try await generateTextResult(request)
            guard !Task.isCancelled else {
                if let toastID {
                    dismissTaskNotificationToast(toastID)
                }
                return
            }

            let normalizedSummary = normalizedRollingMemorySummary(
                result.text,
                maxChars: Self.rollingWorkshopMemoryMaxChars
            )
            guard !normalizedSummary.isEmpty else {
                finishTaskWarningToast(toastID, "Workshop memory update returned no content.")
                return
            }

            // Re-read session state after async boundary to avoid stale counters.
            guard let latestSessionIndex = workshopSessionIndex(for: sessionID) else {
                if let toastID {
                    dismissTaskNotificationToast(toastID)
                }
                return
            }
            let latestCount = project.workshopSessions[latestSessionIndex].messages.filter {
                !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count

            project.rollingWorkshopMemoryBySession[key] = RollingWorkshopMemory(
                summary: normalizedSummary,
                summarizedMessageCount: latestCount,
                updatedAt: .now
            )
            saveProject(debounced: true)
            finishTaskSuccessToast(toastID, "Workshop memory updated.")
        } catch is CancellationError {
            if let toastID {
                dismissTaskNotificationToast(toastID)
            }
        } catch {
            finishTaskErrorToast(toastID, "Workshop memory update failed.")
        }
    }

    private func appendWorkshopMessage(_ message: WorkshopMessage, to sessionID: UUID) {
        guard let index = workshopSessionIndex(for: sessionID) else { return }
        project.workshopSessions[index].messages.append(message)
        project.workshopSessions[index].updatedAt = .now
    }

    private func updateWorkshopMessageContent(sessionID: UUID, messageID: UUID, content: String) {
        guard let sessionIndex = workshopSessionIndex(for: sessionID),
              let messageIndex = project.workshopSessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        project.workshopSessions[sessionIndex].messages[messageIndex].content = content
        project.workshopSessions[sessionIndex].messages[messageIndex].createdAt = .now
        project.workshopSessions[sessionIndex].updatedAt = .now
    }

    private func updateWorkshopMessageUsage(sessionID: UUID, messageID: UUID, usage: TokenUsage?) {
        guard let sessionIndex = workshopSessionIndex(for: sessionID),
              let messageIndex = project.workshopSessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        project.workshopSessions[sessionIndex].messages[messageIndex].usage = usage
        project.workshopSessions[sessionIndex].updatedAt = .now
    }

    private func removeWorkshopMessageIfEmpty(sessionID: UUID, messageID: UUID) {
        guard let sessionIndex = workshopSessionIndex(for: sessionID),
              let messageIndex = project.workshopSessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let content = project.workshopSessions[sessionIndex].messages[messageIndex].content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            project.workshopSessions[sessionIndex].messages.remove(at: messageIndex)
            project.workshopSessions[sessionIndex].updatedAt = .now
        }
    }

    private func normalizedTokenUsage(
        from providerUsage: TokenUsage?,
        request: TextGenerationRequest,
        response: String
    ) -> TokenUsage {
        let estimatedPromptTokens = estimateTokenCount(for: request.systemPrompt + "\n\n" + request.userPrompt)
        let estimatedCompletionTokens = estimateTokenCount(for: response)
        let estimatedTotalTokens = estimatedPromptTokens + estimatedCompletionTokens

        guard let providerUsage else {
            return TokenUsage(
                promptTokens: estimatedPromptTokens,
                completionTokens: estimatedCompletionTokens,
                totalTokens: estimatedTotalTokens,
                isEstimated: true
            )
        }

        let promptTokens = providerUsage.promptTokens ?? estimatedPromptTokens
        let completionTokens = providerUsage.completionTokens ?? estimatedCompletionTokens
        let totalTokens = providerUsage.totalTokens ?? (promptTokens + completionTokens)

        return TokenUsage(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            isEstimated: providerUsage.isEstimated || providerUsage.promptTokens == nil || providerUsage.completionTokens == nil || providerUsage.totalTokens == nil
        )
    }

    private func estimateTokenCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let characterBasedEstimate = Int(ceil(Double(trimmed.count) / 4.0))
        let wordBasedEstimate = Int(ceil(Double(trimmed.split(whereSeparator: \.isWhitespace).count) * 1.3))
        return max(1, max(characterBasedEstimate, wordBasedEstimate))
    }

    private func normalizedRollingMemorySummary(_ value: String, maxChars: Int) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        guard maxChars > 0 else { return "" }
        return normalized.count > maxChars ? String(normalized.prefix(maxChars)) : normalized
    }

    private func stableContentHash(_ value: String) -> String {
        // FNV-1a 64-bit hash for deterministic lightweight content fingerprints.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private func chapter(for chapterID: UUID) -> Chapter? {
        guard let index = chapterIndex(for: chapterID) else { return nil }
        return project.chapters[index]
    }

    private func chapterIDForScene(_ sceneID: UUID?) -> UUID? {
        guard let sceneID,
              let location = sceneLocation(for: sceneID) else {
            return nil
        }
        return project.chapters[location.chapterIndex].id
    }

    private func scene(for sceneID: UUID) -> Scene? {
        guard let location = sceneLocation(for: sceneID) else { return nil }
        return project.chapters[location.chapterIndex].scenes[location.sceneIndex]
    }

    private func chapterSourceFingerprint(chapter: Chapter) -> String {
        let sceneComponents = chapter.scenes.map { scene in
            "\(scene.id.uuidString):\(stableContentHash(scene.content))"
        }
        return stableContentHash(sceneComponents.joined(separator: "|"))
    }

    private func chapterSourceText(
        chapter: Chapter,
        upToSceneID: UUID? = nil,
        maxChars: Int? = nil
    ) -> String {
        var chunks: [String] = []
        for (index, scene) in chapter.scenes.enumerated() {
            let content = scene.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                let sceneTitle = displaySceneTitle(scene)
                chunks.append("Scene \(index + 1): \(sceneTitle)\n\(content)")
            }
            if let upToSceneID, scene.id == upToSceneID {
                break
            }
        }
        let combined = chunks.joined(separator: "\n\n")
        guard let maxChars, maxChars > 0 else { return combined }
        return combined.count > maxChars ? String(combined.prefix(maxChars)) : combined
    }

    private func chunkTextByCharacters(_ text: String, maxChars: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, maxChars > 0 else { return [] }

        let chunkLimit = min(maxChars, Self.rollingChapterMemorySourceChars)
        var chunks: [String] = []
        var start = trimmed.startIndex
        while start < trimmed.endIndex {
            let end = trimmed.index(start, offsetBy: chunkLimit, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            let chunk = trimmed[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(String(chunk))
            }
            start = end
        }
        return chunks
    }

    private func chapterMemorySourceChunks(
        chapter: Chapter,
        source: ChapterRollingMemorySceneSource
    ) throws -> [ChapterMemorySourceChunk] {
        let scenesWithIndex: [(index: Int, scene: Scene)] = {
            switch source {
            case .fullChapter:
                return Array(chapter.scenes.enumerated()).map { ($0.offset, $0.element) }
            case .currentScene:
                guard let selectedSceneID,
                      let index = chapter.scenes.firstIndex(where: { $0.id == selectedSceneID }) else {
                    return []
                }
                return [(index: index, scene: chapter.scenes[index])]
            case .upToSelectedScene:
                guard let selectedSceneID,
                      let index = chapter.scenes.firstIndex(where: { $0.id == selectedSceneID }) else {
                    return []
                }
                return Array(chapter.scenes.prefix(index + 1).enumerated()).map { ($0.offset, $0.element) }
            }
        }()

        guard !scenesWithIndex.isEmpty else {
            switch source {
            case .fullChapter:
                throw AIServiceError.badResponse("Selected chapter has no scenes.")
            case .currentScene:
                throw AIServiceError.badResponse("Select a scene in this chapter first.")
            case .upToSelectedScene:
                throw AIServiceError.badResponse("Select a scene in this chapter first.")
            }
        }

        var chunks: [ChapterMemorySourceChunk] = []
        for (sceneIndex, scene) in scenesWithIndex {
            let sceneContent = scene.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sceneContent.isEmpty else { continue }

            let sceneTitle = displaySceneTitle(scene)
            let sceneLabel = "Scene \(sceneIndex + 1): \(sceneTitle)"
            let sceneChunks = chunkTextByCharacters(
                sceneContent,
                maxChars: Self.rollingChapterMemorySceneChunkChars
            )

            for (chunkIndex, chunkText) in sceneChunks.enumerated() {
                let label: String = {
                    if sceneChunks.count == 1 {
                        return sceneLabel
                    }
                    return "\(sceneLabel) (part \(chunkIndex + 1))"
                }()
                chunks.append(
                    ChapterMemorySourceChunk(
                        label: label,
                        text: "\(label)\n\(chunkText)"
                    )
                )
            }
        }

        return chunks
    }

    private func mergeChapterRollingMemory(
        chapterTitle: String,
        existingMemory: String,
        sourceText: String,
        sourceLabel: String? = nil
    ) async throws -> String {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            throw AIServiceError.badResponse("Source text is empty.")
        }

        let sourceExcerpt = String(trimmedSource.prefix(Self.rollingChapterMemorySourceChars))
        let normalizedExistingMemory = existingMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSourceLabel = sourceLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sourceLabelLine = normalizedSourceLabel.isEmpty ? "" : "SOURCE_SEGMENT: \(normalizedSourceLabel)\n\n"

        let systemPrompt = """
        You maintain concise long-lived memory for a single fiction chapter.

        Output rules:
        - Return plain prose bullets or short paragraphs only.
        - Keep stable facts, chapter-level decisions, continuity constraints, unresolved questions, and arc-level shifts.
        - Remove repetition and low-value narration details.
        - Do not invent facts not present in input.
        """

        let userPrompt = """
        CHAPTER: \(chapterTitle)

        EXISTING_MEMORY:
        <<<
        \(normalizedExistingMemory)
        >>>

        \(sourceLabelLine)SOURCE_TEXT:
        <<<
        \(sourceExcerpt)
        >>>

        TASK:
        Update the chapter memory by merging EXISTING_MEMORY with SOURCE_TEXT. Keep the result compact and high-signal.
        """

        let request = TextGenerationRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: resolvedPrimaryModel(),
            temperature: min(project.settings.temperature, 0.3),
            maxTokens: min(project.settings.maxTokens, 1000)
        )

        let result = try await generateTextResult(request)
        let normalizedSummary = normalizedRollingMemorySummary(
            result.text,
            maxChars: Self.rollingChapterMemoryMaxChars
        )
        guard !normalizedSummary.isEmpty else {
            throw AIServiceError.badResponse("Chapter memory update was empty.")
        }
        return normalizedSummary
    }

    private func buildWorkshopUserPrompt(sessionID: UUID, pendingUserInput: String? = nil) -> PromptRenderer.Result {
        guard let sessionIndex = workshopSessionIndex(for: sessionID) else {
            return PromptRenderer.Result(renderedText: "", warnings: [])
        }

        var messages = project.workshopSessions[sessionIndex].messages
        let trimmedPending = pendingUserInput?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mentionSourceText: String?

        if pendingUserInput != nil {
            if let trimmedPending, !trimmedPending.isEmpty {
                messages.append(WorkshopMessage(role: .user, content: trimmedPending))
            }
            mentionSourceText = trimmedPending?.isEmpty == false ? trimmedPending : nil
        } else {
            mentionSourceText = messages.reversed().first(where: { $0.role == .user })?.content
        }

        let recentMessages = messages.suffix(14)
        let transcript = recentMessages
            .map { msg in
                let prefix = msg.role == .user ? "User" : "Assistant"
                return "\(prefix): \(msg.content)"
            }
            .joined(separator: "\n\n")

        let conversationTurns = messages.map { message in
            PromptRenderer.ChatTurn(
                roleLabel: message.role == .user ? "User" : "Assistant",
                content: message.content
            )
        }

        let sceneContext: String
        let sceneFullText: String
        if workshopUseSceneContext, let scene = selectedScene {
            sceneContext = String(scene.content.suffix(Self.workshopSceneTailChars))
            sceneFullText = scene.content
        } else {
            sceneContext = ""
            sceneFullText = ""
        }

        let contextSections = buildCompendiumContextSections(
            for: selectedScene?.id,
            mentionSourceText: mentionSourceText,
            includeSelectedSceneContext: workshopUseCompendiumContext
        )

        let prompt = activeWorkshopPrompt ?? defaultPromptTemplate(for: .workshop)
        let template = prompt.userTemplate

        let sceneTitle = selectedScene.map { displaySceneTitle($0) } ?? "No scene selected"
        let chapterTitleText = selectedScene.map { self.chapterTitle(forSceneID: $0.id) } ?? "No chapter selected"
        let selectedSessionName = project.workshopSessions[sessionIndex].name.trimmingCharacters(in: .whitespacesAndNewlines)

        return renderPromptTemplate(
            template: template,
            fallbackTemplate: fallbackUserTemplate(for: prompt, category: .workshop),
            beat: "",
            selection: trimmedPending ?? "",
            sceneID: workshopUseSceneContext ? selectedScene?.id : nil,
            sceneExcerpt: sceneContext,
            sceneFullText: sceneFullText,
            sceneTitle: sceneTitle,
            chapterTitle: chapterTitleText,
            contextSections: contextSections,
            conversation: transcript,
            conversationTurns: conversationTurns,
            summaryScope: "",
            source: transcript,
            workshopSessionID: sessionID,
            extraVariables: [
                "chat_name": selectedSessionName.isEmpty ? "Untitled Chat" : selectedSessionName,
                "last_user_message": messages.reversed().first(where: { $0.role == .user })?.content ?? "",
                "last_assistant_message": messages.reversed().first(where: { $0.role == .assistant })?.content ?? ""
            ]
        )
    }

    private func resolvedWorkshopSystemPrompt() -> String {
        if let template = activeWorkshopPrompt?.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
           !template.isEmpty {
            return activeWorkshopPrompt!.systemTemplate
        }
        return "You are an experienced writing coach. Provide concise, practical guidance and concrete alternatives."
    }

    private var shouldUseStreaming: Bool {
        project.settings.provider.supportsStreaming && project.settings.enableStreaming
    }

    private func generateTextResult(
        _ request: TextGenerationRequest,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async throws -> TextGenerationResult {
        switch project.settings.provider {
        case .anthropic:
            return try await anthropicService.generateTextResult(
                request,
                settings: project.settings,
                onPartial: onPartial
            )
        case .openAI, .openRouter, .lmStudio, .openAICompatible:
            return try await openAIService.generateTextResult(
                request,
                settings: project.settings,
                onPartial: onPartial
            )
        }
    }

    private func generateText(
        _ request: TextGenerationRequest,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        switch project.settings.provider {
        case .anthropic:
            return try await anthropicService.generateText(
                request,
                settings: project.settings,
                onPartial: onPartial
            )
        case .openAI, .openRouter, .lmStudio, .openAICompatible:
            return try await openAIService.generateText(
                request,
                settings: project.settings,
                onPartial: onPartial
            )
        }
    }

    private struct MentionResolvedContext {
        var compendiumEntries: [CompendiumEntry] = []
        var sceneReferences: [(chapterTitle: String, sceneTitle: String, summary: String)] = []

        var isEmpty: Bool {
            compendiumEntries.isEmpty && sceneReferences.isEmpty
        }
    }

    private func buildCompendiumContextSections(
        for sceneID: UUID?,
        mentionSourceText: String? = nil,
        includeSelectedSceneContext: Bool = true
    ) -> SceneContextSections {
        let selectedEntries: [CompendiumEntry]
        let selectedSceneSummaries: [(chapterTitle: String, sceneTitle: String, summary: String)]
        let selectedChapterSummaries: [(chapterTitle: String, summary: String)]

        if includeSelectedSceneContext {
            let selectedEntryIDs = compendiumContextIDs(for: sceneID)
            selectedEntries = compendiumEntries(forIDs: selectedEntryIDs)

            let selectedSceneSummaryIDs = sceneSummaryContextIDs(for: sceneID)
            selectedSceneSummaries = sceneSummaryEntries(forIDs: selectedSceneSummaryIDs)

            let selectedChapterSummaryIDs = chapterSummaryContextIDs(for: sceneID)
            selectedChapterSummaries = chapterSummaryEntries(forIDs: selectedChapterSummaryIDs)
        } else {
            selectedEntries = []
            selectedSceneSummaries = []
            selectedChapterSummaries = []
        }

        let mentionContext = resolveMentionContext(from: mentionSourceText)

        let mergedCompendiumEntries = mergeCompendiumEntries(
            selectedEntries,
            mentionContext.compendiumEntries
        )
        let mergedSceneSummaries = mergeSceneContext(
            selectedSceneSummaries,
            mentionContext.sceneReferences
        )

        let compendiumText = mergedCompendiumEntries.map { entry in
            let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = entry.tags.isEmpty ? "" : " [tags: \(entry.tags.joined(separator: ", "))]"
            return "- [\(entry.category.label)] \(entry.title)\(tags): \(body)"
        }

        let sceneSummariesText = mergedSceneSummaries.map { item in
            "- [Scene Summary] \(item.chapterTitle) / \(item.sceneTitle): \(item.summary)"
        }

        let chapterSummariesText = selectedChapterSummaries.map { item in
            "- [Chapter Summary] \(item.chapterTitle): \(item.summary)"
        }

        var combinedLines: [String] = []
        combinedLines.append(contentsOf: compendiumText)
        combinedLines.append(contentsOf: sceneSummariesText)
        combinedLines.append(contentsOf: chapterSummariesText)

        let combined = combinedLines.isEmpty ? "" : combinedLines.joined(separator: "\n")

        return SceneContextSections(
            combined: combined,
            compendium: compendiumText.joined(separator: "\n"),
            sceneSummaries: sceneSummariesText.joined(separator: "\n"),
            chapterSummaries: chapterSummariesText.joined(separator: "\n")
        )
    }

    private func mergedContextWithRolling(context: String, rolling: String) -> String {
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRolling = rolling.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRolling.isEmpty {
            return trimmedContext
        }
        if trimmedContext.isEmpty {
            return trimmedRolling
        }
        return "\(trimmedRolling)\n\(trimmedContext)"
    }

    private func combinedRollingSummaryText(
        chapterRolling: String,
        sceneRolling: String,
        workshopRolling: String
    ) -> String {
        var lines: [String] = []
        let trimmedWorkshop = workshopRolling.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWorkshop.isEmpty {
            lines.append("- [Rolling Workshop Memory] \(trimmedWorkshop)")
        }

        let trimmedChapter = chapterRolling.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedChapter.isEmpty {
            lines.append("- [Rolling Chapter Memory] \(trimmedChapter)")
        }

        let trimmedScene = sceneRolling.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedScene.isEmpty {
            lines.append("- [Rolling Scene Memory] \(trimmedScene)")
        }

        return lines.joined(separator: "\n")
    }

    private func rollingWorkshopSummary(for sessionID: UUID?) -> String {
        guard let sessionID else { return "" }
        let key = sessionID.uuidString
        return project.rollingWorkshopMemoryBySession[key]?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func rollingSceneSummary(for sceneID: UUID?) -> String {
        guard let sceneID,
              let scene = scene(for: sceneID) else {
            return ""
        }

        let key = sceneID.uuidString
        guard let memory = project.rollingSceneMemoryByScene[key] else {
            return ""
        }

        let summary = memory.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            return ""
        }

        let currentHash = stableContentHash(scene.content)
        guard memory.sourceContentHash == currentHash else {
            return ""
        }

        return summary
    }

    private func rollingChapterSummary(for chapterID: UUID?) -> String {
        guard let chapterID,
              let chapter = chapter(for: chapterID) else {
            return ""
        }

        let key = chapterID.uuidString
        guard let memory = project.rollingChapterMemoryByChapter[key] else {
            return ""
        }

        let summary = memory.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            return ""
        }

        let currentFingerprint = chapterSourceFingerprint(chapter: chapter)
        let storedFingerprint = memory.sourceFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveFingerprint = storedFingerprint.isEmpty ? currentFingerprint : storedFingerprint
        guard effectiveFingerprint == currentFingerprint else {
            return ""
        }

        return summary
    }

    private func previewNotes(base: [String], renderWarnings: [String]) -> [String] {
        guard !renderWarnings.isEmpty else {
            return base
        }
        let warningNotes = renderWarnings.map { warning in
            "Template warning: \(warning)"
        }
        return base + warningNotes
    }

    private func displaySceneTitle(_ scene: Scene) -> String {
        let trimmed = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Scene" : trimmed
    }

    private func searchSnippet(
        in searchText: NSString,
        matchRange: NSRange,
        contextCharacters: Int = 70
    ) -> String {
        let lowerBound = max(0, matchRange.location - contextCharacters)
        let upperBound = min(
            searchText.length,
            matchRange.location + matchRange.length + contextCharacters
        )
        let windowRange = NSRange(
            location: lowerBound,
            length: max(0, upperBound - lowerBound)
        )
        let windowText = searchText.substring(with: windowRange)
        let compact = windowText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix = lowerBound > 0 ? "…" : ""
        let suffix = upperBound < searchText.length ? "…" : ""
        return prefix + compact + suffix
    }

    private func displayChapterTitle(_ chapter: Chapter) -> String {
        let trimmed = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chapter" : trimmed
    }

    private func displayCompendiumEntryTitle(_ entry: CompendiumEntry) -> String {
        let trimmed = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Entry" : trimmed
    }

    private func displayWorkshopSessionTitle(_ session: WorkshopSession) -> String {
        let trimmed = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chat" : trimmed
    }

    private func selectGlobalSearchResult(step: Int) -> GlobalSearchResult? {
        guard !globalSearchResults.isEmpty else {
            selectedGlobalSearchResultID = nil
            return nil
        }

        let selectedIndex: Int
        if let selectedGlobalSearchResultID,
           let index = globalSearchResults.firstIndex(where: { $0.id == selectedGlobalSearchResultID }) {
            selectedIndex = index
        } else {
            selectedIndex = step >= 0 ? -1 : 0
        }

        let resultCount = globalSearchResults.count
        let nextIndex = (selectedIndex + step + resultCount) % resultCount
        let nextResult = globalSearchResults[nextIndex]
        selectedGlobalSearchResultID = nextResult.id
        return nextResult
    }

    private func searchGlobalContent(
        _ query: String,
        scope: GlobalSearchScope,
        caseSensitive: Bool = false,
        maxResults: Int = 300
    ) -> [GlobalSearchResult] {
        guard isProjectOpen else { return [] }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        let compareOptions: NSString.CompareOptions = caseSensitive
            ? []
            : [.caseInsensitive, .diacriticInsensitive]

        var output: [GlobalSearchResult] = []

        switch scope {
        case .all:
            for chapter in project.chapters {
                for scene in chapter.scenes {
                    appendSceneMatches(
                        in: chapter,
                        scene: scene,
                        query: normalizedQuery,
                        options: compareOptions,
                        maxResults: maxResults,
                        output: &output
                    )
                    if output.count >= maxResults { return output }
                }
            }
            appendCompendiumMatches(
                query: normalizedQuery,
                options: compareOptions,
                maxResults: maxResults,
                output: &output
            )
            if output.count >= maxResults { return output }
            appendSummaryMatches(
                query: normalizedQuery,
                options: compareOptions,
                maxResults: maxResults,
                output: &output
            )
            if output.count >= maxResults { return output }
            appendNotesMatches(
                query: normalizedQuery,
                options: compareOptions,
                maxResults: maxResults,
                output: &output
            )
            if output.count >= maxResults { return output }
            appendChatMatches(
                query: normalizedQuery,
                options: compareOptions,
                maxResults: maxResults,
                output: &output
            )

        case .scene:
            guard let sceneID = selectedSceneID,
                  let location = sceneLocation(for: sceneID) else {
                return []
            }
            let chapter = project.chapters[location.chapterIndex]
            let scene = chapter.scenes[location.sceneIndex]
            appendSceneMatches(
                in: chapter,
                scene: scene,
                query: normalizedQuery,
                options: compareOptions,
                maxResults: maxResults,
                output: &output
            )

        case .project:
            for chapter in project.chapters {
                for scene in chapter.scenes {
                    appendSceneMatches(
                        in: chapter,
                        scene: scene,
                        query: normalizedQuery,
                        options: compareOptions,
                        maxResults: maxResults,
                        output: &output
                    )
                    if output.count >= maxResults {
                        return output
                    }
                }
            }

        case .compendium:
            appendCompendiumMatches(
                query: normalizedQuery,
                options: compareOptions,
                maxResults: maxResults,
                output: &output
            )

        case .summaries:
            appendSummaryMatches(
                query: normalizedQuery,
                options: compareOptions,
                maxResults: maxResults,
                output: &output
            )

        case .notes:
            appendNotesMatches(
                query: normalizedQuery,
                options: compareOptions,
                maxResults: maxResults,
                output: &output
            )

        case .chats:
            appendChatMatches(
                query: normalizedQuery,
                options: compareOptions,
                maxResults: maxResults,
                output: &output
            )
        }

        return output
    }

    private func appendSearchMatches(
        query: String,
        in searchableText: String,
        options: NSString.CompareOptions,
        output: inout [GlobalSearchResult],
        maxResults: Int,
        makeResult: (NSRange, NSString) -> GlobalSearchResult
    ) {
        let searchableNSString = searchableText as NSString
        guard searchableNSString.length > 0 else { return }

        var searchStart = 0
        while searchStart < searchableNSString.length {
            guard output.count < maxResults else { return }

            let searchRange = NSRange(
                location: searchStart,
                length: searchableNSString.length - searchStart
            )
            let foundRange = searchableNSString.range(
                of: query,
                options: options,
                range: searchRange
            )
            guard foundRange.location != NSNotFound else { break }

            output.append(makeResult(foundRange, searchableNSString))
            searchStart = foundRange.location + max(foundRange.length, 1)
        }
    }

    private func appendSceneMatches(
        in chapter: Chapter,
        scene: Scene,
        query: String,
        options: NSString.CompareOptions,
        maxResults: Int,
        output: inout [GlobalSearchResult]
    ) {
        let chapterTitle = displayChapterTitle(chapter)
        let sceneTitle = displaySceneTitle(scene)
        appendSearchMatches(
            query: query,
            in: scene.content,
            options: options,
            output: &output,
            maxResults: maxResults
        ) { foundRange, sceneText in
            GlobalSearchResult(
                id: "scene:\(scene.id.uuidString):\(foundRange.location)",
                kind: .scene,
                title: sceneTitle,
                subtitle: chapterTitle,
                snippet: searchSnippet(in: sceneText, matchRange: foundRange),
                chapterID: chapter.id,
                sceneID: scene.id,
                compendiumEntryID: nil,
                workshopSessionID: nil,
                workshopMessageID: nil,
                location: foundRange.location,
                length: foundRange.length
            )
        }
    }

    private func appendCompendiumMatches(
        query: String,
        options: NSString.CompareOptions,
        maxResults: Int,
        output: inout [GlobalSearchResult]
    ) {
        for entry in project.compendium {
            let title = displayCompendiumEntryTitle(entry)
            let body = entry.body
            let tags = entry.tags.joined(separator: " ")

            // Build the searchable text, tracking where the body portion starts
            var parts: [String] = []
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(title)
            }
            let bodyOffset: Int
            let bodyNSLength = (body as NSString).length
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                bodyOffset = parts.reduce(0) { $0 + ($1 as NSString).length + 1 }
                parts.append(body)
            } else {
                bodyOffset = -1
            }
            if !tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(tags)
            }

            let searchableText = parts.joined(separator: "\n")

            let titleNSLength = (title as NSString).length

            appendSearchMatches(
                query: query,
                in: searchableText,
                options: options,
                output: &output,
                maxResults: maxResults
            ) { foundRange, searchableNSString in
                // Provide body-relative location when match is fully within body
                var loc: Int? = nil
                var len: Int? = nil
                var isTitleMatch = false
                if bodyOffset >= 0 {
                    let bodyEnd = bodyOffset + bodyNSLength
                    let matchEnd = foundRange.location + foundRange.length
                    if foundRange.location >= bodyOffset && matchEnd <= bodyEnd {
                        loc = foundRange.location - bodyOffset
                        len = foundRange.length
                    }
                }
                // Provide title-relative location when match is fully within title
                if loc == nil && titleNSLength > 0 {
                    let matchEnd = foundRange.location + foundRange.length
                    if matchEnd <= titleNSLength {
                        loc = foundRange.location
                        len = foundRange.length
                        isTitleMatch = true
                    }
                }

                return GlobalSearchResult(
                    id: "compendium:\(entry.id.uuidString):\(foundRange.location)",
                    kind: .compendium,
                    title: title,
                    subtitle: "Compendium • \(entry.category.label)",
                    snippet: searchSnippet(in: searchableNSString, matchRange: foundRange),
                    chapterID: nil,
                    sceneID: nil,
                    compendiumEntryID: entry.id,
                    workshopSessionID: nil,
                    workshopMessageID: nil,
                    location: loc,
                    length: len,
                    isCompendiumTitleMatch: isTitleMatch
                )
            }

            if output.count >= maxResults {
                return
            }
        }
    }

    private func appendSummaryMatches(
        query: String,
        options: NSString.CompareOptions,
        maxResults: Int,
        output: inout [GlobalSearchResult]
    ) {
        for chapter in project.chapters {
            let chapterTitle = displayChapterTitle(chapter)
            let chapterSummary = chapter.summary
            if !chapterSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendSearchMatches(
                    query: query,
                    in: chapterSummary,
                    options: options,
                    output: &output,
                    maxResults: maxResults
                ) { foundRange, summaryText in
                    GlobalSearchResult(
                        id: "chapter-summary:\(chapter.id.uuidString):\(foundRange.location)",
                        kind: .chapterSummary,
                        title: chapterTitle,
                        subtitle: "Chapter Summary",
                        snippet: searchSnippet(in: summaryText, matchRange: foundRange),
                        chapterID: chapter.id,
                        sceneID: nil,
                        compendiumEntryID: nil,
                        workshopSessionID: nil,
                        workshopMessageID: nil,
                        location: foundRange.location,
                        length: foundRange.length
                    )
                }
            }

            if output.count >= maxResults {
                return
            }

            for scene in chapter.scenes {
                let sceneSummary = scene.summary
                guard !sceneSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                let sceneTitle = displaySceneTitle(scene)
                appendSearchMatches(
                    query: query,
                    in: sceneSummary,
                    options: options,
                    output: &output,
                    maxResults: maxResults
                ) { foundRange, summaryText in
                    GlobalSearchResult(
                        id: "scene-summary:\(scene.id.uuidString):\(foundRange.location)",
                        kind: .sceneSummary,
                        title: sceneTitle,
                        subtitle: "\(chapterTitle) • Scene Summary",
                        snippet: searchSnippet(in: summaryText, matchRange: foundRange),
                        chapterID: chapter.id,
                        sceneID: scene.id,
                        compendiumEntryID: nil,
                        workshopSessionID: nil,
                        workshopMessageID: nil,
                        location: foundRange.location,
                        length: foundRange.length
                    )
                }

                if output.count >= maxResults {
                    return
                }
            }
        }
    }

    private func appendNotesMatches(
        query: String,
        options: NSString.CompareOptions,
        maxResults: Int,
        output: inout [GlobalSearchResult]
    ) {
        let projectTitle = currentProjectName
        let projectNotes = project.notes
        if !projectNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendSearchMatches(
                query: query,
                in: projectNotes,
                options: options,
                output: &output,
                maxResults: maxResults
            ) { foundRange, notesText in
                GlobalSearchResult(
                    id: "project-note:\(foundRange.location)",
                    kind: .projectNote,
                    title: projectTitle,
                    subtitle: "Project Notes",
                    snippet: searchSnippet(in: notesText, matchRange: foundRange),
                    chapterID: nil,
                    sceneID: nil,
                    compendiumEntryID: nil,
                    workshopSessionID: nil,
                    workshopMessageID: nil,
                    location: foundRange.location,
                    length: foundRange.length
                )
            }
        }

        if output.count >= maxResults {
            return
        }

        for chapter in project.chapters {
            let chapterTitle = displayChapterTitle(chapter)
            let chapterNotes = chapter.notes
            if !chapterNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendSearchMatches(
                    query: query,
                    in: chapterNotes,
                    options: options,
                    output: &output,
                    maxResults: maxResults
                ) { foundRange, notesText in
                    GlobalSearchResult(
                        id: "chapter-note:\(chapter.id.uuidString):\(foundRange.location)",
                        kind: .chapterNote,
                        title: chapterTitle,
                        subtitle: "Chapter Notes",
                        snippet: searchSnippet(in: notesText, matchRange: foundRange),
                        chapterID: chapter.id,
                        sceneID: nil,
                        compendiumEntryID: nil,
                        workshopSessionID: nil,
                        workshopMessageID: nil,
                        location: foundRange.location,
                        length: foundRange.length
                    )
                }
            }

            if output.count >= maxResults {
                return
            }

            for scene in chapter.scenes {
                let sceneNotes = scene.notes
                guard !sceneNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                let sceneTitle = displaySceneTitle(scene)
                appendSearchMatches(
                    query: query,
                    in: sceneNotes,
                    options: options,
                    output: &output,
                    maxResults: maxResults
                ) { foundRange, notesText in
                    GlobalSearchResult(
                        id: "scene-note:\(scene.id.uuidString):\(foundRange.location)",
                        kind: .sceneNote,
                        title: sceneTitle,
                        subtitle: "\(chapterTitle) • Scene Notes",
                        snippet: searchSnippet(in: notesText, matchRange: foundRange),
                        chapterID: chapter.id,
                        sceneID: scene.id,
                        compendiumEntryID: nil,
                        workshopSessionID: nil,
                        workshopMessageID: nil,
                        location: foundRange.location,
                        length: foundRange.length
                    )
                }

                if output.count >= maxResults {
                    return
                }
            }
        }
    }

    private func appendChatMatches(
        query: String,
        options: NSString.CompareOptions,
        maxResults: Int,
        output: inout [GlobalSearchResult]
    ) {
        for session in project.workshopSessions {
            let sessionTitle = displayWorkshopSessionTitle(session)

            for message in session.messages {
                let messageText = message.content
                guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }

                let roleLabel = message.role == .assistant ? "Assistant" : "You"
                appendSearchMatches(
                    query: query,
                    in: messageText,
                    options: options,
                    output: &output,
                    maxResults: maxResults
                ) { foundRange, searchableNSString in
                    GlobalSearchResult(
                        id: "chat:\(session.id.uuidString):\(message.id.uuidString):\(foundRange.location)",
                        kind: .chatMessage,
                        title: sessionTitle,
                        subtitle: "Chat • \(roleLabel)",
                        snippet: searchSnippet(in: searchableNSString, matchRange: foundRange),
                        chapterID: nil,
                        sceneID: nil,
                        compendiumEntryID: nil,
                        workshopSessionID: session.id,
                        workshopMessageID: message.id,
                        location: foundRange.location,
                        length: foundRange.length
                    )
                }

                if output.count >= maxResults {
                    return
                }
            }
        }
    }

    private func resetGlobalSearchState() {
        searchDebounceTask?.cancel()
        globalSearchQuery = ""
        globalSearchScope = .all
        globalSearchResults = []
        selectedGlobalSearchResultID = nil
        replaceText = ""
        isReplaceMode = false
        pendingSceneSearchSelection = nil
        pendingSceneReplace = nil
        pendingSceneReplaceAll = nil
        pendingWorkshopMessageReveal = nil
        pendingCompendiumTextReveal = nil
        pendingSummaryTextReveal = nil
        pendingNotesTextReveal = nil
        isGlobalSearchVisible = false
        lastGlobalSearchQuery = ""
        lastGlobalSearchScope = .all
    }

    private func chapterTitle(forSceneID sceneID: UUID) -> String {
        guard let location = sceneLocation(for: sceneID) else {
            return "Untitled Chapter"
        }
        return displayChapterTitle(project.chapters[location.chapterIndex])
    }

    private func sceneSummaryText(for sceneID: UUID?) -> String {
        guard let sceneID,
              let location = sceneLocation(for: sceneID) else {
            return ""
        }
        return project.chapters[location.chapterIndex]
            .scenes[location.sceneIndex]
            .summary
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum NarrativeStateBlockStyle {
        case xml
        case compact
    }

    private func narrativeStateBlockStyle(
        template: String,
        fallbackTemplate: String
    ) -> NarrativeStateBlockStyle {
        let resolvedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackTemplate
            : template

        // Compact templates use <<<TAG>>> / <<<END_TAG>>> delimiters.
        if resolvedTemplate.contains("<<<") && resolvedTemplate.contains(">>>") {
            return .compact
        }

        return .xml
    }

    private func narrativeStateVariables(
        for sceneID: UUID?,
        style: NarrativeStateBlockStyle
    ) -> [String: String] {
        guard let normalized = normalizedSceneNarrativeState(sceneNarrativeState(for: sceneID)) else {
            return [
                "state": "",
                "state_pov": "",
                "state_tense": "",
                "state_location": "",
                "state_time": "",
                "state_goal": "",
                "state_emotion": ""
            ]
        }

        let stateBlock: String = {
            switch style {
            case .xml:
                var lines: [String] = []
                if let pov = normalized.pov {
                    lines.append("  <POV>\(pov)</POV>")
                }
                if let tense = normalized.tense {
                    lines.append("  <TENSE>\(tense)</TENSE>")
                }
                if let location = normalized.location {
                    lines.append("  <LOCATION>\(location)</LOCATION>")
                }
                if let time = normalized.time {
                    lines.append("  <TIME>\(time)</TIME>")
                }
                if let goal = normalized.goal {
                    lines.append("  <GOAL>\(goal)</GOAL>")
                }
                if let emotion = normalized.emotion {
                    lines.append("  <EMOTION>\(emotion)</EMOTION>")
                }
                return lines.isEmpty ? "" : "<STATE>\n\(lines.joined(separator: "\n"))\n</STATE>"

            case .compact:
                var lines: [String] = []
                if let pov = normalized.pov {
                    lines.append("POV: \(pov)")
                }
                if let tense = normalized.tense {
                    lines.append("TENSE: \(tense)")
                }
                if let location = normalized.location {
                    lines.append("LOCATION: \(location)")
                }
                if let time = normalized.time {
                    lines.append("TIME: \(time)")
                }
                if let goal = normalized.goal {
                    lines.append("GOAL: \(goal)")
                }
                if let emotion = normalized.emotion {
                    lines.append("EMOTION: \(emotion)")
                }
                return lines.isEmpty ? "" : "STATE:\n\(lines.joined(separator: "\n"))"
            }
        }()

        return [
            "state": stateBlock,
            "state_pov": normalized.pov ?? "",
            "state_tense": normalized.tense ?? "",
            "state_location": normalized.location ?? "",
            "state_time": normalized.time ?? "",
            "state_goal": normalized.goal ?? "",
            "state_emotion": normalized.emotion ?? ""
        ]
    }

    private func resolvePromptPreviewSceneContext() -> PromptPreviewSceneContext {
        if let selectedScene {
            return PromptPreviewSceneContext(
                sceneID: selectedScene.id,
                sceneTitle: displaySceneTitle(selectedScene),
                chapterTitle: chapterTitle(forSceneID: selectedScene.id),
                sceneContent: selectedScene.content,
                note: nil
            )
        }

        for chapter in project.chapters {
            if let firstScene = chapter.scenes.first {
                return PromptPreviewSceneContext(
                    sceneID: firstScene.id,
                    sceneTitle: displaySceneTitle(firstScene),
                    chapterTitle: displayChapterTitle(chapter),
                    sceneContent: firstScene.content,
                    note: "No scene selected. Preview used the first scene in the project."
                )
            }
        }

        return PromptPreviewSceneContext(
            sceneID: nil,
            sceneTitle: "No Scene",
            chapterTitle: "No Chapter",
            sceneContent: "No scene text available.",
            note: "Project has no scenes. Preview used placeholder scene text."
        )
    }

    private func renderPromptTemplate(
        template: String,
        fallbackTemplate: String,
        beat: String,
        selection: String,
        sceneID: UUID?,
        chapterID: UUID? = nil,
        sceneExcerpt: String,
        sceneFullText: String,
        sceneTitle: String,
        chapterTitle: String,
        contextSections: SceneContextSections,
        conversation: String,
        conversationTurns: [PromptRenderer.ChatTurn],
        summaryScope: String,
        source: String,
        workshopSessionID: UUID? = nil,
        extraVariables: [String: String] = [:]
    ) -> PromptRenderer.Result {
        let stateStyle = narrativeStateBlockStyle(
            template: template,
            fallbackTemplate: fallbackTemplate
        )

        let resolvedChapterID = chapterID ?? chapterIDForScene(sceneID)
        let rollingChapter = rollingChapterSummary(for: resolvedChapterID)
        let rollingScene = rollingSceneSummary(for: sceneID)
        let rollingWorkshop = rollingWorkshopSummary(for: workshopSessionID)
        let rollingCombined = combinedRollingSummaryText(
            chapterRolling: rollingChapter,
            sceneRolling: rollingScene,
            workshopRolling: rollingWorkshop
        )
        let contextWithRolling = mergedContextWithRolling(
            context: contextSections.combined,
            rolling: rollingCombined
        )

        var variables: [String: String] = [
            "beat": beat,
            "selection": selection,
            "scene": sceneExcerpt,
            "scene_full": sceneFullText,
            "scene_title": sceneTitle,
            "chapter_title": chapterTitle,
            "context": contextWithRolling,
            "context_compendium": contextSections.compendium,
            "context_scene_summaries": contextSections.sceneSummaries,
            "context_chapter_summaries": contextSections.chapterSummaries,
            "context_rolling": rollingCombined,
            "rolling_summary": rollingCombined,
            "rolling_chapter_summary": rollingChapter,
            "rolling_scene_summary": rollingScene,
            "rolling_workshop_summary": rollingWorkshop,
            "conversation": conversation,
            "summary_scope": summaryScope,
            "source": source,
            "project_title": currentProjectName
        ]

        for (key, value) in narrativeStateVariables(for: sceneID, style: stateStyle) {
            variables[key] = value
        }

        for (key, value) in extraVariables {
            variables[key] = value
        }

        return promptRenderer.render(
            template: template,
            fallbackTemplate: fallbackTemplate,
            context: PromptRenderer.Context(
                variables: variables,
                sceneFullText: sceneFullText,
                conversationTurns: conversationTurns,
                contextSections: [
                    "context": contextWithRolling,
                    "context_compendium": contextSections.compendium,
                    "context_scene_summaries": contextSections.sceneSummaries,
                    "context_chapter_summaries": contextSections.chapterSummaries,
                    "context_rolling": rollingCombined
                ]
            )
        )
    }

    private func resolveMentionContext(from sourceText: String?) -> MentionResolvedContext {
        guard let sourceText else { return MentionResolvedContext() }
        let tokens = MentionParsing.extractMentionTokens(from: sourceText)
        guard !tokens.isEmpty else { return MentionResolvedContext() }

        var context = MentionResolvedContext()

        if !tokens.tags.isEmpty {
            context.compendiumEntries = project.compendium.filter { entry in
                let titleKey = MentionParsing.normalize(entry.title)
                if !titleKey.isEmpty,
                   mentionTagTokenSet(tokens.tags, matches: titleKey) {
                    return true
                }
                return entry.tags.contains { tag in
                    mentionTagTokenSet(tokens.tags, matches: MentionParsing.normalize(tag))
                }
            }
        }

        if !tokens.scenes.isEmpty {
            var references: [(chapterTitle: String, sceneTitle: String, summary: String)] = []

            for chapter in project.chapters {
                let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Untitled Chapter"
                    : chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)

                for scene in chapter.scenes {
                    let sceneTitle = scene.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Untitled Scene"
                        : scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sceneKey = MentionParsing.normalize(sceneTitle)
                    guard mentionTagTokenSet(tokens.scenes, matches: sceneKey) else { continue }

                    var content = scene.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    if content.isEmpty {
                        content = String(scene.content.suffix(Self.workshopSceneTailChars))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    guard !content.isEmpty else { continue }

                    references.append(
                        (chapterTitle: chapterTitle, sceneTitle: sceneTitle, summary: content)
                    )
                }
            }

            context.sceneReferences = references
        }

        return context
    }

    private func mentionTagTokenSet(_ tokens: Set<String>, matches key: String) -> Bool {
        guard !key.isEmpty else { return false }
        return tokens.contains(key)
    }

    private func mergeCompendiumEntries(
        _ selected: [CompendiumEntry],
        _ mentioned: [CompendiumEntry]
    ) -> [CompendiumEntry] {
        var merged = selected
        var seen = Set(selected.map(\.id))
        for entry in mentioned where seen.insert(entry.id).inserted {
            merged.append(entry)
        }
        return merged
    }

    private func mergeSceneContext(
        _ selected: [(chapterTitle: String, sceneTitle: String, summary: String)],
        _ mentioned: [(chapterTitle: String, sceneTitle: String, summary: String)]
    ) -> [(chapterTitle: String, sceneTitle: String, summary: String)] {
        var merged = selected
        var seen = Set(selected.map { key in
            "\(MentionParsing.normalize(key.chapterTitle))::\(MentionParsing.normalize(key.sceneTitle))::\(MentionParsing.normalize(key.summary))"
        })

        for item in mentioned {
            let key = "\(MentionParsing.normalize(item.chapterTitle))::\(MentionParsing.normalize(item.sceneTitle))::\(MentionParsing.normalize(item.summary))"
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }
        return merged
    }

    private func buildChapterSceneSummaryContext(chapter: Chapter) -> String {
        let excerpt = chapter.scenes.enumerated().map { index, scene in
            let title = scene.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled Scene"
                : scene.title.trimmingCharacters(in: .whitespacesAndNewlines)

            let summary = scene.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty {
                return "\(index + 1). \(title): [No scene summary yet]"
            }

            return "\(index + 1). \(title): \(summary)"
        }

        if excerpt.isEmpty {
            return "No scenes available in this chapter."
        }
        return excerpt.joined(separator: "\n")
    }

    private func compendiumContextIDs(for sceneID: UUID?) -> [UUID] {
        guard let sceneID else { return [] }
        return project.sceneContextCompendiumSelection[sceneID.uuidString] ?? []
    }

    private func sceneSummaryContextIDs(for sceneID: UUID?) -> [UUID] {
        guard let sceneID else { return [] }
        let selected = project.sceneContextSceneSummarySelection[sceneID.uuidString] ?? []
        let available = Set(
            project.chapters
                .flatMap(\.scenes)
                .filter { !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map(\.id)
        )
        return selected.filter { available.contains($0) }
    }

    private func chapterSummaryContextIDs(for sceneID: UUID?) -> [UUID] {
        guard let sceneID else { return [] }
        let selected = project.sceneContextChapterSummarySelection[sceneID.uuidString] ?? []
        let available = Set(
            project.chapters
                .filter { !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map(\.id)
        )
        return selected.filter { available.contains($0) }
    }

    private func sceneNarrativeState(for sceneID: UUID?) -> SceneNarrativeState {
        guard let sceneID else { return SceneNarrativeState() }
        guard let rawState = project.sceneNarrativeStates[sceneID.uuidString] else {
            return SceneNarrativeState()
        }
        return normalizedSceneNarrativeState(rawState) ?? SceneNarrativeState()
    }

    private func setSceneNarrativeState(_ state: SceneNarrativeState, for sceneID: UUID) {
        let key = sceneID.uuidString
        if let normalized = normalizedSceneNarrativeState(state) {
            project.sceneNarrativeStates[key] = normalized
        } else {
            project.sceneNarrativeStates.removeValue(forKey: key)
        }
        saveProject(debounced: true)
    }

    private func updateSelectedSceneNarrativeStateValue(
        _ keyPath: WritableKeyPath<SceneNarrativeState, String?>,
        value: String?
    ) {
        guard let selectedSceneID else { return }
        var state = sceneNarrativeState(for: selectedSceneID)
        state[keyPath: keyPath] = value
        setSceneNarrativeState(state, for: selectedSceneID)
    }

    private func normalizedSceneNarrativeState(_ state: SceneNarrativeState) -> SceneNarrativeState? {
        let normalized = SceneNarrativeState(
            pov: normalizedSceneNarrativeValue(state.pov),
            tense: normalizedSceneNarrativeValue(state.tense),
            location: normalizedSceneNarrativeValue(state.location),
            time: normalizedSceneNarrativeValue(state.time),
            goal: normalizedSceneNarrativeValue(state.goal),
            emotion: normalizedSceneNarrativeValue(state.emotion)
        )
        if normalized.pov == nil,
           normalized.tense == nil,
           normalized.location == nil,
           normalized.time == nil,
           normalized.goal == nil,
           normalized.emotion == nil {
            return nil
        }
        return normalized
    }

    private func normalizedSceneNarrativeValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func toggledContextSelectionID(_ id: UUID, in currentIDs: [UUID]) -> [UUID] {
        var updated = currentIDs
        if let index = updated.firstIndex(of: id) {
            updated.remove(at: index)
        } else {
            updated.append(id)
        }
        return updated
    }

    private func normalizedContextSelectionIDs(_ ids: [UUID], validIDs: Set<UUID>) -> [UUID] {
        var deduplicated: [UUID] = []
        var seen = Set<UUID>()

        for id in ids where validIDs.contains(id) {
            if seen.insert(id).inserted {
                deduplicated.append(id)
            }
        }

        return deduplicated
    }

    private func setSceneContextSelection(
        _ ids: [UUID],
        for sceneID: UUID,
        validIDs: Set<UUID>,
        storage: WritableKeyPath<StoryProject, [String: [UUID]]>
    ) {
        let normalized = normalizedContextSelectionIDs(ids, validIDs: validIDs)
        let key = sceneID.uuidString
        if normalized.isEmpty {
            project[keyPath: storage].removeValue(forKey: key)
        } else {
            project[keyPath: storage][key] = normalized
        }
        saveProject(debounced: true)
    }

    private func sanitizedSceneContextSelection(
        _ selection: [String: [UUID]],
        validSceneKeys: Set<String>,
        validIDs: Set<UUID>
    ) -> [String: [UUID]] {
        var sanitized: [String: [UUID]] = [:]

        for (sceneKey, ids) in selection where validSceneKeys.contains(sceneKey) {
            let normalized = normalizedContextSelectionIDs(ids, validIDs: validIDs)
            if !normalized.isEmpty {
                sanitized[sceneKey] = normalized
            }
        }

        return sanitized
    }

    private func setCompendiumContextIDs(_ entryIDs: [UUID], for sceneID: UUID) {
        setSceneContextSelection(
            entryIDs,
            for: sceneID,
            validIDs: Set(project.compendium.map(\.id)),
            storage: \.sceneContextCompendiumSelection
        )
    }

    private func setSceneSummaryContextIDs(_ sceneIDs: [UUID], for sceneID: UUID) {
        setSceneContextSelection(
            sceneIDs,
            for: sceneID,
            validIDs: Set(project.chapters.flatMap(\.scenes).map(\.id)),
            storage: \.sceneContextSceneSummarySelection
        )
    }

    private func setChapterSummaryContextIDs(_ chapterIDs: [UUID], for sceneID: UUID) {
        setSceneContextSelection(
            chapterIDs,
            for: sceneID,
            validIDs: Set(project.chapters.map(\.id)),
            storage: \.sceneContextChapterSummarySelection
        )
    }

    private func compendiumEntries(forIDs entryIDs: [UUID]) -> [CompendiumEntry] {
        let map = Dictionary(uniqueKeysWithValues: project.compendium.map { ($0.id, $0) })
        return entryIDs.compactMap { map[$0] }
    }

    private func sceneSummaryEntries(forIDs sceneIDs: [UUID]) -> [(chapterTitle: String, sceneTitle: String, summary: String)] {
        var map: [UUID: (chapterTitle: String, sceneTitle: String, summary: String)] = [:]

        for chapter in project.chapters {
            let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled Chapter"
                : chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)

            for scene in chapter.scenes {
                let sceneTitle = scene.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Untitled Scene"
                    : scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = scene.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !summary.isEmpty else { continue }
                map[scene.id] = (chapterTitle: chapterTitle, sceneTitle: sceneTitle, summary: summary)
            }
        }

        return sceneIDs.compactMap { map[$0] }
    }

    private func chapterSummaryEntries(forIDs chapterIDs: [UUID]) -> [(chapterTitle: String, summary: String)] {
        let map = Dictionary(uniqueKeysWithValues: project.chapters.map { chapter in
            let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled Chapter"
                : chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return (chapter.id, (chapterTitle: chapterTitle, summary: chapter.summary.trimmingCharacters(in: .whitespacesAndNewlines)))
        })

        return chapterIDs.compactMap { id in
            guard let entry = map[id], !entry.summary.isEmpty else { return nil }
            return entry
        }
    }

    private func removeSceneContextSelection(for sceneID: UUID) {
        project.sceneContextCompendiumSelection.removeValue(forKey: sceneID.uuidString)
        project.sceneContextSceneSummarySelection.removeValue(forKey: sceneID.uuidString)
        project.sceneContextChapterSummarySelection.removeValue(forKey: sceneID.uuidString)
        project.sceneNarrativeStates.removeValue(forKey: sceneID.uuidString)
        project.rollingSceneMemoryByScene.removeValue(forKey: sceneID.uuidString)
    }

    private func removeCompendiumEntryFromSceneContextSelections(_ entryID: UUID) {
        let keys = project.sceneContextCompendiumSelection.keys
        for key in keys {
            guard var ids = project.sceneContextCompendiumSelection[key] else { continue }
            ids.removeAll { $0 == entryID }
            if ids.isEmpty {
                project.sceneContextCompendiumSelection.removeValue(forKey: key)
            } else {
                project.sceneContextCompendiumSelection[key] = ids
            }
        }
    }

    private func removeSceneSummaryFromSceneContextSelections(_ sceneID: UUID) {
        let keys = project.sceneContextSceneSummarySelection.keys
        for key in keys {
            guard var ids = project.sceneContextSceneSummarySelection[key] else { continue }
            ids.removeAll { $0 == sceneID }
            if ids.isEmpty {
                project.sceneContextSceneSummarySelection.removeValue(forKey: key)
            } else {
                project.sceneContextSceneSummarySelection[key] = ids
            }
        }
    }

    private func removeChapterSummaryFromSceneContextSelections(_ chapterID: UUID) {
        let keys = project.sceneContextChapterSummarySelection.keys
        for key in keys {
            guard var ids = project.sceneContextChapterSummarySelection[key] else { continue }
            ids.removeAll { $0 == chapterID }
            if ids.isEmpty {
                project.sceneContextChapterSummarySelection.removeValue(forKey: key)
            } else {
                project.sceneContextChapterSummarySelection[key] = ids
            }
        }
    }

    private func sanitizeSceneContextSelections() {
        let validSceneKeys = Set(
            project.chapters
                .flatMap(\.scenes)
                .map(\.id.uuidString)
        )
        project.sceneContextCompendiumSelection = sanitizedSceneContextSelection(
            project.sceneContextCompendiumSelection,
            validSceneKeys: validSceneKeys,
            validIDs: Set(project.compendium.map(\.id))
        )
        project.sceneContextSceneSummarySelection = sanitizedSceneContextSelection(
            project.sceneContextSceneSummarySelection,
            validSceneKeys: validSceneKeys,
            validIDs: Set(project.chapters.flatMap(\.scenes).map(\.id))
        )
        project.sceneContextChapterSummarySelection = sanitizedSceneContextSelection(
            project.sceneContextChapterSummarySelection,
            validSceneKeys: validSceneKeys,
            validIDs: Set(project.chapters.map(\.id))
        )
    }

    private func sanitizeSceneNarrativeStates() {
        let validSceneIDs = Set(
            project.chapters
                .flatMap(\.scenes)
                .map(\.id.uuidString)
        )

        var sanitized: [String: SceneNarrativeState] = [:]
        for (sceneKey, state) in project.sceneNarrativeStates where validSceneIDs.contains(sceneKey) {
            if let normalized = normalizedSceneNarrativeState(state) {
                sanitized[sceneKey] = normalized
            }
        }
        project.sceneNarrativeStates = sanitized
    }

    private func sanitizeInputHistories() {
        let validSceneKeys = Set(
            project.chapters
                .flatMap(\.scenes)
                .map(\.id.uuidString)
        )
        var sanitizedBeatHistoryByScene: [String: [String]] = [:]
        for (sceneKey, entries) in project.beatInputHistoryByScene where validSceneKeys.contains(sceneKey) {
            let normalized = normalizedHistoryEntries(entries)
            if !normalized.isEmpty {
                sanitizedBeatHistoryByScene[sceneKey] = normalized
            }
        }
        project.beatInputHistoryByScene = sanitizedBeatHistoryByScene

        let validSessionKeys = Set(project.workshopSessions.map(\.id.uuidString))
        var sanitizedWorkshopHistoryBySession: [String: [String]] = [:]
        for (sessionKey, entries) in project.workshopInputHistoryBySession where validSessionKeys.contains(sessionKey) {
            let normalized = normalizedHistoryEntries(entries)
            if !normalized.isEmpty {
                sanitizedWorkshopHistoryBySession[sessionKey] = normalized
            }
        }
        project.workshopInputHistoryBySession = sanitizedWorkshopHistoryBySession
    }

    private func sanitizeRollingMemories() {
        let sessionMessageCountByKey = Dictionary(
            uniqueKeysWithValues: project.workshopSessions.map { ($0.id.uuidString, $0.messages.count) }
        )

        var sanitizedWorkshopMemory: [String: RollingWorkshopMemory] = [:]
        for (sessionKey, memory) in project.rollingWorkshopMemoryBySession {
            guard let messageCount = sessionMessageCountByKey[sessionKey] else { continue }
            let summary = normalizedRollingMemorySummary(
                memory.summary,
                maxChars: Self.rollingWorkshopMemoryMaxChars
            )
            guard !summary.isEmpty else { continue }
            sanitizedWorkshopMemory[sessionKey] = RollingWorkshopMemory(
                summary: summary,
                summarizedMessageCount: min(max(0, memory.summarizedMessageCount), messageCount),
                updatedAt: memory.updatedAt
            )
        }
        project.rollingWorkshopMemoryBySession = sanitizedWorkshopMemory

        let sceneByKey = Dictionary(
            uniqueKeysWithValues: project.chapters.flatMap(\.scenes).map { ($0.id.uuidString, $0) }
        )
        var sanitizedSceneMemory: [String: RollingSceneMemory] = [:]
        for (sceneKey, memory) in project.rollingSceneMemoryByScene {
            guard let scene = sceneByKey[sceneKey] else { continue }
            let summary = normalizedRollingMemorySummary(
                memory.summary,
                maxChars: Self.rollingSceneMemoryMaxChars
            )
            guard !summary.isEmpty else { continue }
            let resolvedHash: String = {
                let normalizedHash = memory.sourceContentHash.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalizedHash.isEmpty ? stableContentHash(scene.content) : normalizedHash
            }()
            sanitizedSceneMemory[sceneKey] = RollingSceneMemory(
                summary: summary,
                sourceContentHash: resolvedHash,
                updatedAt: memory.updatedAt
            )
        }
        project.rollingSceneMemoryByScene = sanitizedSceneMemory

        let chapterByKey = Dictionary(
            uniqueKeysWithValues: project.chapters.map { ($0.id.uuidString, $0) }
        )
        var sanitizedChapterMemory: [String: RollingChapterMemory] = [:]
        for (chapterKey, memory) in project.rollingChapterMemoryByChapter {
            guard let chapter = chapterByKey[chapterKey] else { continue }
            let summary = normalizedRollingMemorySummary(
                memory.summary,
                maxChars: Self.rollingChapterMemoryMaxChars
            )
            guard !summary.isEmpty else { continue }
            let resolvedFingerprint: String = {
                let normalizedFingerprint = memory.sourceFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalizedFingerprint.isEmpty
                    ? chapterSourceFingerprint(chapter: chapter)
                    : normalizedFingerprint
            }()
            sanitizedChapterMemory[chapterKey] = RollingChapterMemory(
                summary: summary,
                sourceFingerprint: resolvedFingerprint,
                updatedAt: memory.updatedAt
            )
        }
        project.rollingChapterMemoryByChapter = sanitizedChapterMemory
    }

    private struct GenerationAppendBase {
        let content: String
        let richTextData: Data?
    }

    private struct GeneratedSceneContent {
        let content: String
        let richTextData: Data?
    }

    private func appendGeneratedText(_ generatedText: String) {
        guard let selectedSceneID,
              let base = makeGenerationAppendBase(for: selectedSceneID),
              let location = sceneLocation(for: selectedSceneID) else {
            return
        }

        let trimmedIncoming = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIncoming.isEmpty else { return }

        let updatedContent = buildGeneratedSceneContent(base: base, generated: trimmedIncoming)
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].content = updatedContent.content
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].contentRTFData = updatedContent.richTextData
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].updatedAt = .now
    }

    private func makeGenerationAppendBase(for sceneID: UUID) -> GenerationAppendBase? {
        guard let location = sceneLocation(for: sceneID) else {
            return nil
        }

        let scene = project.chapters[location.chapterIndex].scenes[location.sceneIndex]
        var current = scene.content
        var currentRichTextData = scene.contentRTFData

        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n\n"
            let appearance = project.editorAppearance
            let baseFont = resolvedEditorBaseFont(from: appearance)
            let textColor = resolvedEditorTextColor(from: appearance)
            let paragraphStyle = resolvedEditorParagraphStyle(from: appearance)

            let attributed = makeAttributedSceneContent(
                plainText: scene.content,
                richTextData: scene.contentRTFData
            )
            attributed.append(
                NSAttributedString(
                    string: "\n\n",
                    attributes: [
                        .font: baseFont,
                        .foregroundColor: textColor,
                        .paragraphStyle: paragraphStyle
                    ]
                )
            )
            currentRichTextData = makeRTFData(from: attributed)
        }

        return GenerationAppendBase(content: current, richTextData: currentRichTextData)
    }

    private func setGeneratedTextPreview(sceneID: UUID, base: GenerationAppendBase, generated: String) {
        guard let location = sceneLocation(for: sceneID) else {
            return
        }

        let updatedContent = buildGeneratedSceneContent(base: base, generated: generated)
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].content = updatedContent.content
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].contentRTFData = updatedContent.richTextData
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].updatedAt = .now
    }

    private func buildGeneratedSceneContent(base: GenerationAppendBase, generated: String) -> GeneratedSceneContent {
        let composed = makeAttributedSceneContent(
            plainText: base.content,
            richTextData: base.richTextData
        )

        if !generated.isEmpty {
            let appearance = project.editorAppearance
            let baseFont = resolvedEditorBaseFont(from: appearance)
            let textColor = resolvedEditorTextColor(from: appearance)
            let paragraphStyle = resolvedEditorParagraphStyle(from: appearance)
            composed.append(
                applyEditorAppearanceToAttributedText(
                    makeGeneratedMarkdownAttributedText(
                        from: generated,
                        baseFont: baseFont
                    ),
                    textColor: textColor,
                    paragraphStyle: paragraphStyle
                )
            )
        }

        return GeneratedSceneContent(
            content: composed.string,
            richTextData: makeRTFData(from: composed)
        )
    }

    private func applyEditorAppearanceToAttributedText(
        _ attributed: NSAttributedString,
        textColor: NSColor,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else { return mutable }

        mutable.beginEditing()
        mutable.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        mutable.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            let adjustedStyle = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            adjustedStyle.lineHeightMultiple = paragraphStyle.lineHeightMultiple
            adjustedStyle.alignment = paragraphStyle.alignment
            adjustedStyle.lineBreakMode = .byWordWrapping
            adjustedStyle.firstLineHeadIndent = paragraphStyle.firstLineHeadIndent
            mutable.addAttribute(.paragraphStyle, value: adjustedStyle, range: range)
        }
        mutable.endEditing()

        return mutable
    }

    private func makeGeneratedMarkdownAttributedText(from text: String, baseFont: NSFont) -> NSAttributedString {
        let markdownOptions = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )

        if let parsed = try? AttributedString(markdown: text, options: markdownOptions) {
            return normalizeMarkdownFonts(
                NSAttributedString(parsed),
                baseFont: baseFont
            )
        }

        return NSAttributedString(string: text, attributes: [.font: baseFont])
    }

    private func normalizeMarkdownFonts(_ attributed: NSAttributedString, baseFont: NSFont) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let adjustedFont: NSFont
            if let parsedFont = value as? NSFont {
                adjustedFont = mapMarkdownFontTraits(parsedFont, onto: baseFont)
            } else {
                adjustedFont = baseFont
            }
            mutable.addAttribute(.font, value: adjustedFont, range: range)
        }

        return mutable
    }

    private func mapMarkdownFontTraits(_ parsedFont: NSFont, onto baseFont: NSFont) -> NSFont {
        let fontManager = NSFontManager.shared
        let traits = fontManager.traits(of: parsedFont)
        var mapped = baseFont

        if traits.contains(.boldFontMask) {
            mapped = fontManager.convert(mapped, toHaveTrait: .boldFontMask)
        }
        if traits.contains(.italicFontMask) {
            mapped = fontManager.convert(mapped, toHaveTrait: .italicFontMask)
        }

        return mapped
    }

    private func makeAttributedSceneContent(plainText: String, richTextData: Data?) -> NSMutableAttributedString {
        if let richTextData,
           let attributed = try? NSAttributedString(
            data: richTextData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
           ) {
            return NSMutableAttributedString(attributedString: attributed)
        }

        let appearance = project.editorAppearance
        return NSMutableAttributedString(
            string: plainText,
            attributes: [
                .font: resolvedEditorBaseFont(from: appearance),
                .foregroundColor: resolvedEditorTextColor(from: appearance),
                .paragraphStyle: resolvedEditorParagraphStyle(from: appearance)
            ]
        )
    }

    private func makeRTFData(from attributed: NSAttributedString) -> Data? {
        let range = NSRange(location: 0, length: attributed.length)
        return try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    private func resolvedEditorBaseFont(from settings: EditorAppearanceSettings) -> NSFont {
        let normalizedFamily = SceneFontSelectorData.normalizedFamily(settings.fontFamily)
        if normalizedFamily == SceneFontSelectorData.systemFamily {
            if settings.fontSize > 0 {
                return NSFont.systemFont(ofSize: settings.fontSize)
            }
            return NSFont.preferredFont(forTextStyle: .body)
        }

        let size = settings.fontSize > 0 ? settings.fontSize : NSFont.systemFontSize
        return NSFont(name: normalizedFamily, size: size) ?? NSFont.preferredFont(forTextStyle: .body)
    }

    private func resolvedEditorTextColor(from settings: EditorAppearanceSettings) -> NSColor {
        if let color = settings.textColor {
            return NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        }
        return NSColor.textColor
    }

    private func resolvedEditorParagraphStyle(from settings: EditorAppearanceSettings) -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = max(1.0, settings.lineHeightMultiple)
        paragraphStyle.alignment = nsTextAlignment(from: settings.textAlignment)
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.firstLineHeadIndent = max(0, settings.paragraphIndent)
        return paragraphStyle
    }

    private func nsTextAlignment(from option: TextAlignmentOption) -> NSTextAlignment {
        switch option {
        case .left:
            return .left
        case .center:
            return .center
        case .right:
            return .right
        case .justified:
            return .justified
        }
    }

    private func sceneLocation(for sceneID: UUID) -> SceneLocation? {
        sceneLocation(for: sceneID, in: project)
    }

    private func sceneLocation(for sceneID: UUID, in project: StoryProject) -> SceneLocation? {
        for chapterIndex in project.chapters.indices {
            if let sceneIndex = project.chapters[chapterIndex].scenes.firstIndex(where: { $0.id == sceneID }) {
                return SceneLocation(chapterIndex: chapterIndex, sceneIndex: sceneIndex)
            }
        }
        return nil
    }

    private func chapterIndex(for chapterID: UUID) -> Int? {
        project.chapters.firstIndex(where: { $0.id == chapterID })
    }

    private func compendiumIndex(for entryID: UUID) -> Int? {
        project.compendium.firstIndex(where: { $0.id == entryID })
    }

    private func workshopSessionIndex(for sessionID: UUID) -> Int? {
        project.workshopSessions.firstIndex(where: { $0.id == sessionID })
    }

    private func promptIndex(for promptID: UUID) -> Int? {
        project.prompts.firstIndex(where: { $0.id == promptID })
    }

    private func ensureValidSelections() {
        guard isProjectOpen else { return }
        sanitizeSceneContextSelections()
        sanitizeSceneNarrativeStates()
        sanitizeInputHistories()
        sanitizeRollingMemories()

        if let selectedSceneID,
           sceneLocation(for: selectedSceneID) == nil {
            self.selectedSceneID = nil
        }

        if selectedSceneID == nil {
            self.selectedSceneID = project.chapters
                .flatMap(\.scenes)
                .first?.id
        }

        if let selectedSceneID,
           let location = sceneLocation(for: selectedSceneID) {
            selectedChapterID = project.chapters[location.chapterIndex].id
        } else if selectedChapterID == nil {
            selectedChapterID = project.chapters.first?.id
        }

        if project.selectedSceneID != self.selectedSceneID {
            project.selectedSceneID = self.selectedSceneID
        }

        if let selectedCompendiumID,
           compendiumIndex(for: selectedCompendiumID) == nil {
            self.selectedCompendiumID = nil
        }

        if selectedCompendiumID == nil {
            selectedCompendiumID = project.compendium.first?.id
        }

        if let selectedPromptID = project.selectedProsePromptID,
           promptIndex(for: selectedPromptID) == nil {
            project.selectedProsePromptID = prosePrompts.first?.id
        } else if project.selectedProsePromptID == nil {
            project.selectedProsePromptID = prosePrompts.first?.id
        }

        if let selectedRewritePromptID = project.selectedRewritePromptID,
           promptIndex(for: selectedRewritePromptID) == nil {
            project.selectedRewritePromptID = rewritePrompts.first?.id
        } else if project.selectedRewritePromptID == nil {
            project.selectedRewritePromptID = rewritePrompts.first?.id
        }

        if let selectedSummaryPromptID = project.selectedSummaryPromptID,
           promptIndex(for: selectedSummaryPromptID) == nil {
            project.selectedSummaryPromptID = summaryPrompts.first?.id
        } else if project.selectedSummaryPromptID == nil {
            project.selectedSummaryPromptID = summaryPrompts.first?.id
        }

        if let selectedWorkshopPromptID = project.selectedWorkshopPromptID,
           promptIndex(for: selectedWorkshopPromptID) == nil {
            project.selectedWorkshopPromptID = workshopPrompts.first?.id
        } else if project.selectedWorkshopPromptID == nil {
            project.selectedWorkshopPromptID = workshopPrompts.first?.id
        }

        if project.workshopSessions.isEmpty {
            let session = Self.makeInitialWorkshopSession(name: "Chat 1")
            project.workshopSessions = [session]
            project.selectedWorkshopSessionID = session.id
            selectedWorkshopSessionID = session.id
        }

        if let selectedWorkshopSessionID,
           workshopSessionIndex(for: selectedWorkshopSessionID) == nil {
            self.selectedWorkshopSessionID = nil
        }

        if self.selectedWorkshopSessionID == nil {
            self.selectedWorkshopSessionID = project.selectedWorkshopSessionID ?? project.workshopSessions.first?.id
        }

        if project.selectedWorkshopSessionID != self.selectedWorkshopSessionID {
            project.selectedWorkshopSessionID = self.selectedWorkshopSessionID
        }

        syncWorkshopContextTogglesFromSelectedSession()
    }

    private func saveProject(debounced: Bool = false, forceWrite: Bool = false) {
        guard isProjectOpen else { return }
        project.updatedAt = .now
        let shouldWriteToDisk = project.autosaveEnabled || forceWrite

        if isDocumentBacked {
            if debounced {
                autosaveTask?.cancel()
                autosaveTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard let self, !Task.isCancelled else { return }
                    self.documentChangeHandler?(self.project)
                    if shouldWriteToDisk {
                        self.saveCurrentDocumentToDisk()
                    }
                }
                return
            }

            autosaveTask?.cancel()
            documentChangeHandler?(project)
            if shouldWriteToDisk {
                saveCurrentDocumentToDisk()
            }
            return
        }

        guard shouldWriteToDisk else {
            autosaveTask?.cancel()
            return
        }

        if debounced {
            autosaveTask?.cancel()
            autosaveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self, !Task.isCancelled else { return }
                self.writeProjectToDisk()
            }
            return
        }

        autosaveTask?.cancel()
        writeProjectToDisk()
    }

    private func writeProjectToDisk() {
        guard isProjectOpen, let currentProjectURL else { return }

        do {
            self.currentProjectURL = try persistence.saveProject(project, at: currentProjectURL)
        } catch {
            lastError = "Failed to save project: \(error.localizedDescription)"
        }
    }

    private func saveCurrentDocumentToDisk() {
        guard isDocumentBacked, let currentProjectURL else { return }
        let standardizedURL = currentProjectURL.standardizedFileURL

        if let document = NSDocumentController.shared.documents.first(where: {
            $0.fileURL?.standardizedFileURL == standardizedURL
        }) {
            if documentSaveInProgress {
                pendingDocumentSaveRequest = true
                return
            }

            documentSaveInProgress = true
            pendingDocumentSaveRequest = false
            let typeName = document.fileType ?? UTType.sceneProject.identifier
            document.save(
                to: standardizedURL,
                ofType: typeName,
                for: .saveOperation
            ) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.lastError = "Failed to save document: \(error.localizedDescription)"
                }
                self.completeDocumentSaveCycle()
            }
        }
    }

    private func synchronizeDocumentModificationDateIfNeeded() {
        guard isDocumentBacked, let currentProjectURL else { return }
        let standardizedURL = currentProjectURL.standardizedFileURL

        guard let document = NSDocumentController.shared.documents.first(where: {
            $0.fileURL?.standardizedFileURL == standardizedURL
        }) else {
            return
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: standardizedURL.path)
        if let modificationDate = attributes?[.modificationDate] as? Date {
            document.fileModificationDate = modificationDate
        }
    }

    private func completeDocumentSaveCycle() {
        documentSaveInProgress = false

        if pendingDocumentSaveRequest {
            pendingDocumentSaveRequest = false
            saveCurrentDocumentToDisk()
        }
    }

    private func scheduleModelDiscovery(immediate: Bool = false) {
        guard isProjectOpen else { return }
        guard project.settings.provider.supportsModelDiscovery else {
            return
        }

        modelDiscoveryTask?.cancel()
        modelDiscoveryTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            await self.refreshAvailableModels(showErrors: false)
        }
    }
}
