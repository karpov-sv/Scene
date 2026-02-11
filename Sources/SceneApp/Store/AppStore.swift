import Foundation

@MainActor
final class AppStore: ObservableObject {
    struct SceneLocation {
        let chapterIndex: Int
        let sceneIndex: Int
    }

    @Published private(set) var project: StoryProject

    @Published var selectedChapterID: UUID?
    @Published var selectedSceneID: UUID?
    @Published var selectedCompendiumID: UUID?

    @Published var selectedWorkshopSessionID: UUID?
    @Published var workshopInput: String = ""
    @Published var workshopIsGenerating: Bool = false
    @Published var workshopStatus: String = ""
    @Published var workshopUseSceneContext: Bool = true
    @Published var workshopUseCompendiumContext: Bool = true

    @Published var beatInput: String = ""
    @Published var isGenerating: Bool = false
    @Published var generationStatus: String = ""
    @Published var lastError: String?

    @Published var showingSettings: Bool = false

    private let persistence: ProjectPersistence
    private let mockService: LocalMockAIService
    private let openAIService: OpenAICompatibleAIService

    private var autosaveTask: Task<Void, Never>?

    init(
        persistence: ProjectPersistence = .shared,
        mockService: LocalMockAIService = LocalMockAIService(),
        openAIService: OpenAICompatibleAIService = OpenAICompatibleAIService()
    ) {
        self.persistence = persistence
        self.mockService = mockService
        self.openAIService = openAIService

        if let loaded = try? persistence.load() {
            self.project = loaded
        } else {
            self.project = StoryProject.starter()
        }

        // Ensure workshop baseline exists for older saved files.
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

        self.selectedChapterID = project.chapters.first?.id
        self.selectedSceneID = project.chapters.first?.scenes.first?.id
        self.selectedCompendiumID = project.compendium.first?.id
        self.selectedWorkshopSessionID = project.selectedWorkshopSessionID ?? project.workshopSessions.first?.id

        ensureValidSelections()
    }

    deinit {
        autosaveTask?.cancel()
    }

    // MARK: - Read APIs

    var chapters: [Chapter] {
        project.chapters
    }

    var workshopSessions: [WorkshopSession] {
        project.workshopSessions
    }

    var prosePrompts: [PromptTemplate] {
        project.prompts.filter { $0.category == .prose }
    }

    var workshopPrompts: [PromptTemplate] {
        project.prompts.filter { $0.category == .workshop }
    }

    var selectedScene: Scene? {
        guard let selectedSceneID, let location = sceneLocation(for: selectedSceneID) else {
            return nil
        }
        return project.chapters[location.chapterIndex].scenes[location.sceneIndex]
    }

    var selectedCompendiumEntry: CompendiumEntry? {
        guard let selectedCompendiumID, let index = compendiumIndex(for: selectedCompendiumID) else {
            return nil
        }
        return project.compendium[index]
    }

    var selectedWorkshopSession: WorkshopSession? {
        guard let selectedWorkshopSessionID,
              let index = workshopSessionIndex(for: selectedWorkshopSessionID) else {
            return nil
        }
        return project.workshopSessions[index]
    }

    var activeProsePrompt: PromptTemplate? {
        if let selectedID = project.selectedProsePromptID,
           let index = promptIndex(for: selectedID) {
            return project.prompts[index]
        }
        return prosePrompts.first
    }

    var activeWorkshopPrompt: PromptTemplate? {
        if let selectedID = project.selectedWorkshopPromptID,
           let index = promptIndex(for: selectedID) {
            return project.prompts[index]
        }
        return workshopPrompts.first
    }

    func entries(in category: CompendiumCategory) -> [CompendiumEntry] {
        project.compendium
            .filter { $0.category == category }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Selection

    func selectChapter(_ chapterID: UUID) {
        selectedChapterID = chapterID
        if let chapter = project.chapters.first(where: { $0.id == chapterID }),
           let firstScene = chapter.scenes.first {
            selectedSceneID = firstScene.id
        }
    }

    func selectScene(_ sceneID: UUID, chapterID: UUID) {
        selectedChapterID = chapterID
        selectedSceneID = sceneID
    }

    func selectCompendiumEntry(_ entryID: UUID?) {
        selectedCompendiumID = entryID
    }

    func selectWorkshopSession(_ sessionID: UUID) {
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
        saveProject(debounced: true)
    }

    func updateEndpoint(_ endpoint: String) {
        project.settings.endpoint = endpoint
        saveProject(debounced: true)
    }

    func updateAPIKey(_ apiKey: String) {
        project.settings.apiKey = apiKey
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

    func updateDefaultSystemPrompt(_ prompt: String) {
        project.settings.defaultSystemPrompt = prompt
        saveProject(debounced: true)
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
        guard let selectedSceneID,
              let location = sceneLocation(for: selectedSceneID) else {
            return
        }

        project.chapters[location.chapterIndex].scenes[location.sceneIndex].content = content
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

    // MARK: - Workshop

    func setSelectedWorkshopPrompt(_ id: UUID?) {
        project.selectedWorkshopPromptID = id
        saveProject(debounced: true)
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
        workshopStatus = "Thinking..."

        let prompt = buildWorkshopUserPrompt(sessionID: sessionID)
        let systemPrompt = activeWorkshopPrompt?.systemTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? activeWorkshopPrompt!.systemTemplate
            : "You are an experienced writing coach. Provide concise, practical guidance and concrete alternatives."

        let request = TextGenerationRequest(
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            model: project.settings.model,
            temperature: project.settings.temperature,
            maxTokens: project.settings.maxTokens
        )

        defer {
            workshopIsGenerating = false
        }

        do {
            let response = try await generateText(request)
            appendWorkshopMessage(.init(role: .assistant, content: response), to: sessionID)
            workshopStatus = "Response generated."
            project.workshopSessions[sessionIndex].updatedAt = .now
            saveProject()
        } catch {
            workshopStatus = "Chat request failed."
            lastError = error.localizedDescription
            appendWorkshopMessage(
                .init(role: .assistant, content: "I hit an error: \(error.localizedDescription)"),
                to: sessionID
            )
            saveProject()
        }
    }

    // MARK: - Prompts

    func setSelectedProsePrompt(_ id: UUID?) {
        project.selectedProsePromptID = id
        saveProject(debounced: true)
    }

    func addProsePrompt() {
        let prompt = PromptTemplate(
            category: .prose,
            title: "Prompt \(prosePrompts.count + 1)",
            userTemplate: PromptTemplate.defaultProseTemplate.userTemplate,
            systemTemplate: PromptTemplate.defaultProseTemplate.systemTemplate
        )

        project.prompts.append(prompt)
        project.selectedProsePromptID = prompt.id
        saveProject()
    }

    func deleteSelectedProsePrompt() {
        guard let selected = project.selectedProsePromptID,
              let index = promptIndex(for: selected),
              project.prompts[index].category == .prose else {
            return
        }

        let proseCount = prosePrompts.count
        if proseCount <= 1 {
            return
        }

        project.prompts.remove(at: index)
        project.selectedProsePromptID = prosePrompts.first?.id
        saveProject()
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

        isGenerating = true
        generationStatus = "Generating..."

        defer {
            isGenerating = false
        }

        let activePrompt = activeProsePrompt ?? PromptTemplate.defaultProseTemplate
        let sceneContext = String(scene.content.suffix(4500))
        let compendiumContext = buildCompendiumContext(limit: 8)

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

        let request = TextGenerationRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: project.settings.model,
            temperature: project.settings.temperature,
            maxTokens: project.settings.maxTokens
        )

        do {
            let text = try await generateText(request)
            appendGeneratedText(text)
            generationStatus = "Generated \(text.count) characters."
            beatInput = ""
            saveProject()
        } catch {
            lastError = error.localizedDescription
            generationStatus = "Generation failed."
        }
    }

    // MARK: - Helpers

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

    private func buildWorkshopUserPrompt(sessionID: UUID) -> String {
        guard let sessionIndex = workshopSessionIndex(for: sessionID) else {
            return ""
        }

        let session = project.workshopSessions[sessionIndex]
        let transcript = session.messages
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
            compendiumContext = buildCompendiumContext(limit: 10)
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

    private func generateText(_ request: TextGenerationRequest) async throws -> String {
        switch project.settings.provider {
        case .localMock:
            return try await mockService.generateText(request, settings: project.settings)
        case .openAICompatible:
            return try await openAIService.generateText(request, settings: project.settings)
        }
    }

    private func buildCompendiumContext(limit: Int) -> String {
        let excerpt = project.compendium
            .prefix(limit)
            .map { entry in
                let body = String(entry.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(220))
                let tags = entry.tags.isEmpty ? "" : " [tags: \(entry.tags.joined(separator: ", "))]"
                return "- [\(entry.category.label)] \(entry.title)\(tags): \(body)"
            }

        if excerpt.isEmpty {
            return "No compendium context available."
        }

        return excerpt.joined(separator: "\n")
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
        do {
            try persistence.save(project)
        } catch {
            lastError = "Failed to save project: \(error.localizedDescription)"
        }
    }
}
