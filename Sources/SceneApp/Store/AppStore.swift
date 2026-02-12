import Foundation

@MainActor
final class AppStore: ObservableObject {
    struct SceneLocation {
        let chapterIndex: Int
        let sceneIndex: Int
    }

    struct WorkshopPayloadPreview: Identifiable {
        let id: UUID = UUID()
        let providerLabel: String
        let endpointURL: String?
        let method: String?
        let headers: [OpenAICompatibleAIService.RequestPreview.Header]
        let bodyJSON: String
        let notes: [String]
    }

    @Published private(set) var project: StoryProject
    @Published private(set) var isProjectOpen: Bool = false
    @Published private(set) var currentProjectURL: URL?

    @Published var selectedChapterID: UUID?
    @Published var selectedSceneID: UUID?
    @Published var selectedCompendiumID: UUID?

    @Published var selectedWorkshopSessionID: UUID?
    @Published var workshopInput: String = ""
    @Published var workshopIsGenerating: Bool = false
    @Published var workshopStatus: String = ""
    @Published var workshopUseSceneContext: Bool = true
    @Published var workshopUseCompendiumContext: Bool = true
    @Published private(set) var workshopLiveUsage: TokenUsage?

    @Published var beatInput: String = ""
    @Published private(set) var beatInputHistory: [String] = []
    @Published var isGenerating: Bool = false
    @Published var generationStatus: String = ""
    @Published private(set) var proseLiveUsage: TokenUsage?
    @Published var lastError: String?
    @Published private(set) var availableRemoteModels: [String] = []
    @Published var isDiscoveringModels: Bool = false
    @Published var modelDiscoveryStatus: String = ""

    @Published var showingSettings: Bool = false

    private let persistence: ProjectPersistence
    private let mockService: LocalMockAIService
    private let openAIService: OpenAICompatibleAIService

    private var autosaveTask: Task<Void, Never>?
    private var modelDiscoveryTask: Task<Void, Never>?
    private var workshopRequestTask: Task<Void, Never>?
    private var proseRequestTask: Task<Void, Never>?

    init(
        persistence: ProjectPersistence = .shared,
        mockService: LocalMockAIService = LocalMockAIService(),
        openAIService: OpenAICompatibleAIService = OpenAICompatibleAIService()
    ) {
        self.persistence = persistence
        self.mockService = mockService
        self.openAIService = openAIService

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

    deinit {
        autosaveTask?.cancel()
        modelDiscoveryTask?.cancel()
        workshopRequestTask?.cancel()
        proseRequestTask?.cancel()
    }

    // MARK: - Read APIs

    var currentProjectPathDisplay: String {
        currentProjectURL?.path ?? "No project open"
    }

    var currentProjectName: String {
        guard let currentProjectURL else { return "No Project" }
        return currentProjectURL.deletingPathExtension().lastPathComponent
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

    var selectedScene: Scene? {
        guard isProjectOpen else { return nil }
        guard let selectedSceneID, let location = sceneLocation(for: selectedSceneID) else {
            return nil
        }
        return project.chapters[location.chapterIndex].scenes[location.sceneIndex]
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
        if let selectedID = project.selectedProsePromptID,
           let index = promptIndex(for: selectedID) {
            return project.prompts[index]
        }
        return prosePrompts.first
    }

    var activeWorkshopPrompt: PromptTemplate? {
        guard isProjectOpen else { return nil }
        if let selectedID = project.selectedWorkshopPromptID,
           let index = promptIndex(for: selectedID) {
            return project.prompts[index]
        }
        return workshopPrompts.first
    }

    var activeRewritePrompt: PromptTemplate? {
        guard isProjectOpen else { return nil }
        if let selectedID = project.selectedRewritePromptID,
           let index = promptIndex(for: selectedID) {
            return project.prompts[index]
        }
        return rewritePrompts.first
    }

    var activeSummaryPrompt: PromptTemplate? {
        guard isProjectOpen else { return nil }
        if let selectedID = project.selectedSummaryPromptID,
           let index = promptIndex(for: selectedID) {
            return project.prompts[index]
        }
        return summaryPrompts.first
    }

    var workshopInputHistory: [String] {
        guard let session = selectedWorkshopSession else {
            return []
        }

        var seen = Set<String>()
        var output: [String] = []

        for message in session.messages.reversed() where message.role == .user {
            let normalized = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(normalized)
            if output.count >= 30 {
                break
            }
        }

        return output
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

    // MARK: - Selection

    func selectChapter(_ chapterID: UUID) {
        guard isProjectOpen else { return }
        selectedChapterID = chapterID
        if let chapter = project.chapters.first(where: { $0.id == chapterID }),
           let firstScene = chapter.scenes.first {
            selectedSceneID = firstScene.id
        }
    }

    func selectScene(_ sceneID: UUID, chapterID: UUID) {
        guard isProjectOpen else { return }
        selectedChapterID = chapterID
        selectedSceneID = sceneID
    }

    func isCompendiumEntrySelectedForCurrentSceneContext(_ entryID: UUID) -> Bool {
        selectedSceneContextCompendiumIDs.contains(entryID)
    }

    func toggleCompendiumEntryForCurrentSceneContext(_ entryID: UUID) {
        guard selectedSceneID != nil else { return }

        var current = selectedSceneContextCompendiumIDs
        if let index = current.firstIndex(of: entryID) {
            current.remove(at: index)
        } else {
            current.append(entryID)
        }

        setCompendiumContextIDsForCurrentScene(current)
    }

    func clearCurrentSceneContextCompendiumSelection() {
        setCompendiumContextIDsForCurrentScene([])
    }

    func setCompendiumContextIDsForCurrentScene(_ entryIDs: [UUID]) {
        guard let selectedSceneID else { return }
        setCompendiumContextIDs(entryIDs, for: selectedSceneID)
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
        saveProject(debounced: true)
    }

    // MARK: - Project and Settings

    func updateProjectTitle(_ title: String) {
        project.title = title
        saveProject(debounced: true)
    }

    func updateProvider(_ provider: AIProvider) {
        project.settings.provider = provider
        if provider == .openAICompatible {
            scheduleModelDiscovery(immediate: true)
        } else {
            modelDiscoveryTask?.cancel()
            availableRemoteModels = []
            isDiscoveringModels = false
            modelDiscoveryStatus = "Model discovery is available for OpenAI-compatible providers."
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

    func updateDefaultSystemPrompt(_ prompt: String) {
        project.settings.defaultSystemPrompt = prompt
        saveProject(debounced: true)
    }

    func applyLMStudioEndpointPreset() {
        project.settings.provider = .openAICompatible
        project.settings.endpoint = GenerationSettings.lmStudioDefaultEndpoint
        scheduleModelDiscovery(immediate: true)
        saveProject(debounced: true)
    }

    func refreshAvailableModels(force: Bool = false, showErrors: Bool = true) async {
        guard isProjectOpen else {
            availableRemoteModels = []
            modelDiscoveryStatus = ""
            isDiscoveringModels = false
            return
        }

        guard project.settings.provider == .openAICompatible else {
            availableRemoteModels = []
            modelDiscoveryStatus = "Model discovery is available for OpenAI-compatible providers."
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
            let discovered = try await openAIService.fetchAvailableModels(settings: project.settings)
            availableRemoteModels = discovered

            if discovered.isEmpty {
                modelDiscoveryStatus = "No models returned by endpoint."
                return
            }

            modelDiscoveryStatus = "Discovered \(discovered.count) model(s)."

            let currentModel = project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentModel.isEmpty, let first = discovered.first {
                project.settings.model = first
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

    // MARK: - Chapter / Scene

    func addChapter() {
        let chapterNumber = project.chapters.count + 1
        let starterScene = Scene(title: "Scene 1")
        let chapter = Chapter(title: "Chapter \(chapterNumber)", scenes: [starterScene])

        project.chapters.append(chapter)
        selectedChapterID = chapter.id
        selectedSceneID = starterScene.id
        saveProject()
    }

    func deleteChapter(_ chapterID: UUID) {
        project.chapters.removeAll { $0.id == chapterID }

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

        selectedChapterID = project.chapters[chapterIndex].id
        selectedSceneID = scene.id

        saveProject()
    }

    func deleteScene(_ sceneID: UUID) {
        for chapterIndex in project.chapters.indices {
            project.chapters[chapterIndex].scenes.removeAll { $0.id == sceneID }
        }
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

        project.chapters[location.chapterIndex].scenes.swapAt(location.sceneIndex, location.sceneIndex - 1)
        project.chapters[location.chapterIndex].updatedAt = .now
        saveProject()
    }

    func moveSceneDown(_ sceneID: UUID) {
        guard let location = sceneLocation(for: sceneID),
              location.sceneIndex < project.chapters[location.chapterIndex].scenes.count - 1 else {
            return
        }

        project.chapters[location.chapterIndex].scenes.swapAt(location.sceneIndex, location.sceneIndex + 1)
        project.chapters[location.chapterIndex].updatedAt = .now
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
        saveProject(debounced: true)
    }

    func updateSelectedSceneSummary(_ summary: String) {
        guard let selectedSceneID,
              let location = sceneLocation(for: selectedSceneID) else {
            return
        }

        project.chapters[location.chapterIndex].scenes[location.sceneIndex].summary = summary
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].updatedAt = .now
        project.chapters[location.chapterIndex].updatedAt = .now
        saveProject(debounced: true)
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

    func deleteSelectedCompendiumEntry() {
        guard let selectedCompendiumID else { return }
        project.compendium.removeAll { $0.id == selectedCompendiumID }
        removeCompendiumEntryFromSceneContextSelections(selectedCompendiumID)
        self.selectedCompendiumID = project.compendium.first?.id
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

    func submitBeatGeneration() {
        guard proseRequestTask == nil else { return }

        proseRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.proseRequestTask = nil
            }
            await self.generateFromBeat()
        }
    }

    func cancelBeatGeneration() {
        proseRequestTask?.cancel()
        proseLiveUsage = nil
        generationStatus = "Cancelling..."
    }

    func makeProsePayloadPreview() throws -> WorkshopPayloadPreview {
        let beat = beatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !beat.isEmpty else {
            throw AIServiceError.badResponse("Type a beat to preview payload.")
        }

        guard let scene = selectedScene else {
            throw AIServiceError.badResponse("Select a scene first.")
        }

        let request = makeProseGenerationRequest(beat: beat, scene: scene)

        switch project.settings.provider {
        case .openAICompatible:
            let preview = try openAIService.makeChatRequestPreview(request: request, settings: project.settings)
            return WorkshopPayloadPreview(
                providerLabel: project.settings.provider.label,
                endpointURL: preview.url,
                method: preview.method,
                headers: preview.headers,
                bodyJSON: preview.bodyJSON,
                notes: [
                    "Prompt includes beat input, current scene excerpt, and selected scene context entries.",
                    "Streaming is \(project.settings.enableStreaming ? "enabled" : "disabled").",
                    "Timeout is \(Int(project.settings.requestTimeoutSeconds.rounded())) seconds."
                ]
            )
        case .localMock:
            let dictionary: [String: Any] = [
                "provider": project.settings.provider.label,
                "request": [
                    "systemPrompt": request.systemPrompt,
                    "userPrompt": request.userPrompt,
                    "model": request.model,
                    "temperature": request.temperature,
                    "maxTokens": request.maxTokens
                ]
            ]
            let bodyJSON = (try? Self.prettyJSONString(fromJSONObject: dictionary)) ?? "{}"
            return WorkshopPayloadPreview(
                providerLabel: project.settings.provider.label,
                endpointURL: nil,
                method: nil,
                headers: [],
                bodyJSON: bodyJSON,
                notes: ["Local Mock provider is active. This request does not use network transport."]
            )
        }
    }

    func rewriteSelectedSceneText(_ selectedText: String) async throws -> String {
        let normalizedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSelection.isEmpty else {
            throw AIServiceError.badResponse("Select some scene text first.")
        }
        guard let scene = selectedScene else {
            throw AIServiceError.badResponse("Select a scene first.")
        }

        let request = makeRewriteRequest(selectedText: normalizedSelection, scene: scene)
        let rewritten = try await generateText(request)
        let normalizedRewrite = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRewrite.isEmpty else {
            throw AIServiceError.badResponse("Rewrite result was empty.")
        }

        return normalizedRewrite
    }

    func summarizeSelectedScene() async throws -> String {
        guard let scene = selectedScene else {
            throw AIServiceError.badResponse("Select a scene first.")
        }

        let request = makeSummaryRequest(scene: scene)
        let rawSummary = try await generateText(request)
        let normalizedSummary = rawSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSummary.isEmpty else {
            throw AIServiceError.badResponse("Summary result was empty.")
        }

        updateSelectedSceneSummary(normalizedSummary)
        return normalizedSummary
    }

    // MARK: - Workshop

    func applyWorkshopInputFromHistory(_ text: String) {
        workshopInput = text
    }

    func makeWorkshopPayloadPreview() throws -> WorkshopPayloadPreview {
        guard let sessionID = selectedWorkshopSessionID else {
            throw AIServiceError.badResponse("Select a chat session first.")
        }

        let pendingUserInput = workshopInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pendingUserInput.isEmpty else {
            throw AIServiceError.badResponse("Type a message to preview payload.")
        }

        let request = TextGenerationRequest(
            systemPrompt: resolvedWorkshopSystemPrompt(),
            userPrompt: buildWorkshopUserPrompt(sessionID: sessionID, pendingUserInput: pendingUserInput),
            model: project.settings.model,
            temperature: project.settings.temperature,
            maxTokens: project.settings.maxTokens
        )

        switch project.settings.provider {
        case .openAICompatible:
            let preview = try openAIService.makeChatRequestPreview(request: request, settings: project.settings)
            return WorkshopPayloadPreview(
                providerLabel: project.settings.provider.label,
                endpointURL: preview.url,
                method: preview.method,
                headers: preview.headers,
                bodyJSON: preview.bodyJSON,
                notes: [
                    "Streaming is \(project.settings.enableStreaming ? "enabled" : "disabled").",
                    "Timeout is \(Int(project.settings.requestTimeoutSeconds.rounded())) seconds."
                ]
            )
        case .localMock:
            let dictionary: [String: Any] = [
                "provider": project.settings.provider.label,
                "request": [
                    "systemPrompt": request.systemPrompt,
                    "userPrompt": request.userPrompt,
                    "model": request.model,
                    "temperature": request.temperature,
                    "maxTokens": request.maxTokens
                ]
            ]
            let bodyJSON = (try? Self.prettyJSONString(fromJSONObject: dictionary)) ?? "{}"
            return WorkshopPayloadPreview(
                providerLabel: project.settings.provider.label,
                endpointURL: nil,
                method: nil,
                headers: [],
                bodyJSON: bodyJSON,
                notes: ["Local Mock provider is active. This request does not use network transport."]
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
        let session = Self.makeInitialWorkshopSession(name: "Chat \(nextIndex)")
        project.workshopSessions.append(session)
        selectedWorkshopSessionID = session.id
        project.selectedWorkshopSessionID = session.id
        saveProject()
    }

    func canDeleteWorkshopSession(_ sessionID: UUID) -> Bool {
        project.workshopSessions.count > 1 && workshopSessionIndex(for: sessionID) != nil
    }

    func deleteWorkshopSession(_ sessionID: UUID) {
        guard canDeleteWorkshopSession(sessionID) else { return }
        project.workshopSessions.removeAll { $0.id == sessionID }
        ensureValidSelections()
        saveProject()
    }

    func clearWorkshopSessionMessages(_ sessionID: UUID) {
        guard let index = workshopSessionIndex(for: sessionID) else { return }
        project.workshopSessions[index].messages = []
        project.workshopSessions[index].updatedAt = .now
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
        guard !userText.isEmpty else {
            workshopStatus = "Type a message first."
            return
        }
        guard let sessionID = selectedWorkshopSessionID,
              let sessionIndex = workshopSessionIndex(for: sessionID) else {
            workshopStatus = "Select a chat session first."
            return
        }

        appendWorkshopMessage(.init(role: .user, content: userText), to: sessionID)
        workshopInput = ""
        workshopIsGenerating = true
        workshopLiveUsage = nil
        workshopStatus = shouldUseStreaming ? "Streaming..." : "Thinking..."

        let prompt = buildWorkshopUserPrompt(sessionID: sessionID)
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
            model: project.settings.model,
            temperature: project.settings.temperature,
            maxTokens: project.settings.maxTokens
        )

        defer {
            workshopIsGenerating = false
            workshopLiveUsage = nil
        }

        let workshopPartialHandler: (@MainActor (String) -> Void)?
        if shouldUseStreaming {
            workshopPartialHandler = { [weak self] partial in
                guard let self, let messageID = streamingAssistantMessageID else { return }
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
        } catch is CancellationError {
            workshopStatus = "Request cancelled."

            if shouldUseStreaming, let messageID = streamingAssistantMessageID {
                removeWorkshopMessageIfEmpty(sessionID: sessionID, messageID: messageID)
            }

            saveProject()
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

    private func defaultPromptTemplate(for category: PromptCategory) -> PromptTemplate {
        switch category {
        case .prose:
            return PromptTemplate.defaultProseTemplate
        case .workshop:
            return PromptTemplate.defaultWorkshopTemplate
        case .rewrite:
            return PromptTemplate(
                category: .rewrite,
                title: "Rewrite",
                userTemplate: """
                Rewrite the selected passage according to the style and continuity of the scene.

                SELECTED PASSAGE:
                {beat}

                CURRENT SCENE:
                {scene}

                CONTEXT:
                {context}

                Return only the rewritten passage.
                """,
                systemTemplate: "You are a fiction editing assistant. Keep intent and continuity while improving clarity and style."
            )
        case .summary:
            return PromptTemplate(
                category: .summary,
                title: "Summary",
                userTemplate: """
                Summarize the current material clearly and concisely.

                CURRENT SCENE:
                {scene}

                CONTEXT:
                {context}
                """,
                systemTemplate: "You summarize fiction drafts with accurate details and continuity awareness."
            )
        }
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

    func generateFromBeat() async {
        let beat = beatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isGenerating else { return }
        guard !beat.isEmpty else {
            generationStatus = "Enter a beat to generate text."
            return
        }
        guard let scene = selectedScene else {
            generationStatus = "Select a scene first."
            return
        }

        let request = makeProseGenerationRequest(beat: beat, scene: scene)
        rememberBeatInputHistory(beat)

        isGenerating = true
        generationStatus = shouldUseStreaming ? "Streaming..." : "Generating..."
        proseLiveUsage = normalizedTokenUsage(from: nil, request: request, response: "")

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
        } catch is CancellationError {
            proseLiveUsage = nil
            generationStatus = "Generation cancelled."
            saveProject()
        } catch {
            proseLiveUsage = nil
            lastError = error.localizedDescription
            generationStatus = "Generation failed."
        }
    }

    private func makeProseGenerationRequest(beat: String, scene: Scene) -> TextGenerationRequest {
        let activePrompt = activeProsePrompt ?? PromptTemplate.defaultProseTemplate
        let sceneContext = String(scene.content.suffix(4500))
        let compendiumContext = buildCompendiumContext(for: scene.id)

        let userPrompt = expandPrompt(
            template: activePrompt.userTemplate,
            beat: beat,
            scene: sceneContext,
            context: compendiumContext,
            conversation: ""
        )

        let systemPrompt = activePrompt.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? project.settings.defaultSystemPrompt
            : activePrompt.systemTemplate

        return TextGenerationRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: project.settings.model,
            temperature: project.settings.temperature,
            maxTokens: project.settings.maxTokens
        )
    }

    private func makeRewriteRequest(selectedText: String, scene: Scene) -> TextGenerationRequest {
        let prompt = activeRewritePrompt ?? defaultPromptTemplate(for: .rewrite)
        let sceneContext = String(scene.content.suffix(4500))
        let compendiumContext = buildCompendiumContext(for: scene.id)

        let userPrompt = expandPrompt(
            template: prompt.userTemplate,
            beat: selectedText,
            scene: sceneContext,
            context: compendiumContext,
            conversation: ""
        )

        let systemPrompt = prompt.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? project.settings.defaultSystemPrompt
            : prompt.systemTemplate

        return TextGenerationRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: project.settings.model,
            temperature: project.settings.temperature,
            maxTokens: project.settings.maxTokens
        )
    }

    private func makeSummaryRequest(scene: Scene) -> TextGenerationRequest {
        let prompt = activeSummaryPrompt ?? defaultPromptTemplate(for: .summary)
        let sceneContext = String(scene.content.suffix(4500))
        let compendiumContext = buildCompendiumContext(for: scene.id)

        let userPrompt = expandPrompt(
            template: prompt.userTemplate,
            beat: "",
            scene: sceneContext,
            context: compendiumContext,
            conversation: ""
        )

        let systemPrompt = prompt.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? project.settings.defaultSystemPrompt
            : prompt.systemTemplate

        return TextGenerationRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: project.settings.model,
            temperature: project.settings.temperature,
            maxTokens: project.settings.maxTokens
        )
    }

    private func rememberBeatInputHistory(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        beatInputHistory.removeAll { $0 == normalized }
        beatInputHistory.insert(normalized, at: 0)

        if beatInputHistory.count > 30 {
            beatInputHistory.removeLast(beatInputHistory.count - 30)
        }
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
        beatInputHistory = []
        generationStatus = ""
        workshopStatus = ""
        isGenerating = false
        workshopIsGenerating = false
        proseLiveUsage = nil
        workshopLiveUsage = nil
        availableRemoteModels = []
        isDiscoveringModels = false
        modelDiscoveryStatus = ""

        ensureProjectBaseline()

        selectedChapterID = project.chapters.first?.id
        selectedSceneID = project.chapters.first?.scenes.first?.id
        selectedCompendiumID = project.compendium.first?.id
        selectedWorkshopSessionID = project.selectedWorkshopSessionID ?? project.workshopSessions.first?.id

        ensureValidSelections()

        if rememberAsLastOpened, let currentProjectURL {
            persistence.saveLastOpenedProjectURL(currentProjectURL)
        }

        if project.settings.provider == .openAICompatible {
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
        beatInputHistory = []
        generationStatus = ""
        workshopStatus = ""
        isGenerating = false
        workshopIsGenerating = false
        proseLiveUsage = nil
        workshopLiveUsage = nil
        availableRemoteModels = []
        isDiscoveringModels = false
        modelDiscoveryStatus = ""

        if clearLastOpenedReference {
            persistence.clearLastOpenedProjectURL()
        }
    }

    private func persistOpenProjectIfNeeded() throws {
        guard isProjectOpen, let currentProjectURL else { return }

        autosaveTask?.cancel()
        project.updatedAt = .now
        self.currentProjectURL = try persistence.saveProject(project, at: currentProjectURL)
    }

    private func cancelProjectTasksForSwitch() {
        autosaveTask?.cancel()
        modelDiscoveryTask?.cancel()
        workshopRequestTask?.cancel()
        proseRequestTask?.cancel()

        autosaveTask = nil
        modelDiscoveryTask = nil
        workshopRequestTask = nil
        proseRequestTask = nil
    }

    private func ensureProjectBaseline() {
        if !project.prompts.contains(where: { $0.category == .rewrite }) {
            let rewritePrompt = defaultPromptTemplate(for: .rewrite)
            project.prompts.append(rewritePrompt)
            if project.selectedRewritePromptID == nil {
                project.selectedRewritePromptID = rewritePrompt.id
            }
        }

        if !project.prompts.contains(where: { $0.category == .summary }) {
            let summaryPrompt = defaultPromptTemplate(for: .summary)
            project.prompts.append(summaryPrompt)
            if project.selectedSummaryPromptID == nil {
                project.selectedSummaryPromptID = summaryPrompt.id
            }
        }

        if !project.prompts.contains(where: { $0.category == .workshop }) {
            let workshopPrompt = PromptTemplate.defaultWorkshopTemplate
            project.prompts.append(workshopPrompt)
            if project.selectedWorkshopPromptID == nil {
                project.selectedWorkshopPromptID = workshopPrompt.id
            }
        }

        if project.workshopSessions.isEmpty {
            let session = Self.makeInitialWorkshopSession(name: "Chat 1")
            project.workshopSessions = [session]
            project.selectedWorkshopSessionID = session.id
        }
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

    private func buildWorkshopUserPrompt(sessionID: UUID, pendingUserInput: String? = nil) -> String {
        guard let sessionIndex = workshopSessionIndex(for: sessionID) else {
            return ""
        }

        var messages = project.workshopSessions[sessionIndex].messages
        if let pendingUserInput {
            let trimmedPending = pendingUserInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPending.isEmpty {
                messages.append(WorkshopMessage(role: .user, content: trimmedPending))
            }
        }

        let transcript = messages
            .suffix(14)
            .map { msg in
                let prefix = msg.role == .user ? "User" : "Assistant"
                return "\(prefix): \(msg.content)"
            }
            .joined(separator: "\n\n")

        let sceneContext: String
        if workshopUseSceneContext {
            sceneContext = selectedScene.map { String($0.content.suffix(2400)) } ?? "No scene selected."
        } else {
            sceneContext = "Scene context disabled."
        }

        let compendiumContext: String
        if workshopUseCompendiumContext {
            compendiumContext = buildCompendiumContext(for: selectedScene?.id)
        } else {
            compendiumContext = "Compendium context disabled."
        }

        let template = activeWorkshopPrompt?.userTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? activeWorkshopPrompt!.userTemplate
            : PromptTemplate.defaultWorkshopTemplate.userTemplate

        return expandPrompt(
            template: template,
            beat: "",
            scene: sceneContext,
            context: compendiumContext,
            conversation: transcript
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
        project.settings.provider == .openAICompatible && project.settings.enableStreaming
    }

    private func generateTextResult(
        _ request: TextGenerationRequest,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async throws -> TextGenerationResult {
        switch project.settings.provider {
        case .localMock:
            let text = try await mockService.generateText(request, settings: project.settings)
            return TextGenerationResult(text: text, usage: nil)
        case .openAICompatible:
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
        case .localMock:
            return try await mockService.generateText(request, settings: project.settings)
        case .openAICompatible:
            return try await openAIService.generateText(
                request,
                settings: project.settings,
                onPartial: onPartial
            )
        }
    }

    private func buildCompendiumContext(for sceneID: UUID?) -> String {
        let selectedEntryIDs = compendiumContextIDs(for: sceneID)
        let selectedEntries = compendiumEntries(forIDs: selectedEntryIDs)
        return formattedCompendiumContext(entries: selectedEntries)
    }

    private func formattedCompendiumContext(entries: [CompendiumEntry]) -> String {
        let excerpt = entries.map { entry in
            let body = String(entry.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(220))
            let tags = entry.tags.isEmpty ? "" : " [tags: \(entry.tags.joined(separator: ", "))]"
            return "- [\(entry.category.label)] \(entry.title)\(tags): \(body)"
        }

        if excerpt.isEmpty {
            return "No compendium context selected for this scene."
        }

        return excerpt.joined(separator: "\n")
    }

    private func compendiumContextIDs(for sceneID: UUID?) -> [UUID] {
        guard let sceneID else { return [] }
        return project.sceneContextCompendiumSelection[sceneID.uuidString] ?? []
    }

    private func setCompendiumContextIDs(_ entryIDs: [UUID], for sceneID: UUID) {
        let validEntryIDs = Set(project.compendium.map(\.id))
        var deduplicated: [UUID] = []
        var seen = Set<UUID>()
        for entryID in entryIDs where validEntryIDs.contains(entryID) {
            if seen.insert(entryID).inserted {
                deduplicated.append(entryID)
            }
        }

        let key = sceneID.uuidString
        if deduplicated.isEmpty {
            project.sceneContextCompendiumSelection.removeValue(forKey: key)
        } else {
            project.sceneContextCompendiumSelection[key] = deduplicated
        }
        saveProject(debounced: true)
    }

    private func compendiumEntries(forIDs entryIDs: [UUID]) -> [CompendiumEntry] {
        let map = Dictionary(uniqueKeysWithValues: project.compendium.map { ($0.id, $0) })
        return entryIDs.compactMap { map[$0] }
    }

    private func removeSceneContextSelection(for sceneID: UUID) {
        project.sceneContextCompendiumSelection.removeValue(forKey: sceneID.uuidString)
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

    private func sanitizeSceneContextSelections() {
        let validSceneIDs = Set(
            project.chapters
                .flatMap(\.scenes)
                .map(\.id.uuidString)
        )
        let validEntryIDs = Set(project.compendium.map(\.id))

        var sanitized: [String: [UUID]] = [:]
        for (sceneKey, ids) in project.sceneContextCompendiumSelection where validSceneIDs.contains(sceneKey) {
            var unique: [UUID] = []
            var seen = Set<UUID>()
            for id in ids where validEntryIDs.contains(id) {
                if seen.insert(id).inserted {
                    unique.append(id)
                }
            }
            if !unique.isEmpty {
                sanitized[sceneKey] = unique
            }
        }
        project.sceneContextCompendiumSelection = sanitized
    }

    private func expandPrompt(template: String, beat: String, scene: String, context: String, conversation: String) -> String {
        let normalizedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? PromptTemplate.defaultProseTemplate.userTemplate
            : template

        return normalizedTemplate
            .replacingOccurrences(of: "{beat}", with: beat)
            .replacingOccurrences(of: "{scene}", with: scene)
            .replacingOccurrences(of: "{context}", with: context)
            .replacingOccurrences(of: "{conversation}", with: conversation)
    }

    private func appendGeneratedText(_ generatedText: String) {
        guard let selectedSceneID,
              let location = sceneLocation(for: selectedSceneID) else {
            return
        }

        var current = project.chapters[location.chapterIndex].scenes[location.sceneIndex].content
        let trimmedIncoming = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n\n"
        }

        current += trimmedIncoming
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].content = current
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].contentRTFData = nil
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].updatedAt = .now
    }

    private func makeGenerationAppendBase(for sceneID: UUID) -> String? {
        guard let location = sceneLocation(for: sceneID) else {
            return nil
        }

        var current = project.chapters[location.chapterIndex].scenes[location.sceneIndex].content
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n\n"
        }
        return current
    }

    private func setGeneratedTextPreview(sceneID: UUID, base: String, generated: String) {
        guard let location = sceneLocation(for: sceneID) else {
            return
        }

        project.chapters[location.chapterIndex].scenes[location.sceneIndex].content = base + generated
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].contentRTFData = nil
        project.chapters[location.chapterIndex].scenes[location.sceneIndex].updatedAt = .now
    }

    private func sceneLocation(for sceneID: UUID) -> SceneLocation? {
        for chapterIndex in project.chapters.indices {
            if let sceneIndex = project.chapters[chapterIndex].scenes.firstIndex(where: { $0.id == sceneID }) {
                return SceneLocation(chapterIndex: chapterIndex, sceneIndex: sceneIndex)
            }
        }
        return nil
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
    }

    private func saveProject(debounced: Bool = false) {
        guard isProjectOpen else { return }
        project.updatedAt = .now

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

    private static func prettyJSONString(fromJSONObject jsonObject: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func scheduleModelDiscovery(immediate: Bool = false) {
        guard isProjectOpen else { return }
        guard project.settings.provider == .openAICompatible else {
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
