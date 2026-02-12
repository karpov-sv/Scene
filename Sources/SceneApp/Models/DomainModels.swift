import Foundation

enum CompendiumCategory: String, Codable, CaseIterable, Identifiable {
    case characters
    case locations
    case lore
    case items
    case notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .characters:
            return "Characters"
        case .locations:
            return "Locations"
        case .lore:
            return "Lore"
        case .items:
            return "Items"
        case .notes:
            return "Notes"
        }
    }
}

enum PromptCategory: String, Codable, CaseIterable, Identifiable {
    case prose
    case rewrite
    case summary
    case workshop

    var id: String { rawValue }
}

enum SummaryScope: String, Codable, CaseIterable, Identifiable {
    case scene
    case chapter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scene:
            return "Scene"
        case .chapter:
            return "Chapter"
        }
    }
}

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case localMock
    case openAICompatible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .localMock:
            return "Local Mock"
        case .openAICompatible:
            return "OpenAI-Compatible API"
        }
    }
}

struct Scene: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var content: String
    var contentRTFData: Data?
    var summary: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        content: String = "",
        contentRTFData: Data? = nil,
        summary: String = "",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.contentRTFData = contentRTFData
        self.summary = summary
        self.updatedAt = updatedAt
    }
}

struct Chapter: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var scenes: [Scene]
    var summary: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        scenes: [Scene] = [],
        summary: String = "",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.scenes = scenes
        self.summary = summary
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case scenes
        case summary
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        scenes = try container.decode([Scene].self, forKey: .scenes)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}

struct CompendiumEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var category: CompendiumCategory
    var title: String
    var body: String
    var tags: [String]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        category: CompendiumCategory,
        title: String,
        body: String = "",
        tags: [String] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.body = body
        self.tags = tags
        self.updatedAt = updatedAt
    }
}

struct PromptTemplate: Codable, Identifiable, Equatable {
    var id: UUID
    var category: PromptCategory
    var title: String
    var userTemplate: String
    var systemTemplate: String

    init(
        id: UUID = UUID(),
        category: PromptCategory = .prose,
        title: String,
        userTemplate: String,
        systemTemplate: String
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.userTemplate = userTemplate
        self.systemTemplate = systemTemplate
    }

    static let defaultProseTemplate = PromptTemplate(
        title: "Cinematic Prose",
        userTemplate: """
        Continue the scene from this beat.

        BEAT:
        {beat}

        CURRENT SCENE:
        {scene}

        CONTEXT:
        {context}

        Write the next passage only.
        """,
        systemTemplate: "You are a fiction writing assistant. Preserve continuity, voice, and factual consistency. Return prose only."
    )

    static let defaultWorkshopTemplate = PromptTemplate(
        category: .workshop,
        title: "Story Workshop",
        userTemplate: """
        Work with me on this story problem.

        CONTEXT:
        {context}

        CURRENT SCENE:
        {scene}

        CONVERSATION:
        {conversation}
        """,
        systemTemplate: "You are an experienced writing coach helping the user improve scenes, pacing, structure, and character work. Be practical and specific."
    )
}

enum WorkshopRole: String, Codable {
    case user
    case assistant
}

struct WorkshopMessage: Codable, Identifiable, Equatable {
    var id: UUID
    var role: WorkshopRole
    var content: String
    var createdAt: Date
    var usage: TokenUsage?

    init(
        id: UUID = UUID(),
        role: WorkshopRole,
        content: String,
        createdAt: Date = .now,
        usage: TokenUsage? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.usage = usage
    }
}

struct WorkshopSession: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var messages: [WorkshopMessage]
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, messages: [WorkshopMessage] = [], updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

struct GenerationSettings: Codable, Equatable {
    var provider: AIProvider
    var endpoint: String
    var apiKey: String
    var model: String
    var temperature: Double
    var maxTokens: Int
    var enableStreaming: Bool
    var requestTimeoutSeconds: Double
    var defaultSystemPrompt: String

    static let lmStudioDefaultEndpoint = "http://localhost:1234/v1"
    static let ollamaDefaultEndpoint = "http://localhost:11434/v1"

    init(
        provider: AIProvider,
        endpoint: String,
        apiKey: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        enableStreaming: Bool,
        requestTimeoutSeconds: Double,
        defaultSystemPrompt: String
    ) {
        self.provider = provider
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.enableStreaming = enableStreaming
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.defaultSystemPrompt = defaultSystemPrompt
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case endpoint
        case apiKey
        case model
        case temperature
        case maxTokens
        case enableStreaming
        case requestTimeoutSeconds
        case defaultSystemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(AIProvider.self, forKey: .provider)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        model = try container.decode(String.self, forKey: .model)
        temperature = try container.decode(Double.self, forKey: .temperature)
        maxTokens = try container.decode(Int.self, forKey: .maxTokens)
        enableStreaming = try container.decodeIfPresent(Bool.self, forKey: .enableStreaming) ?? false
        requestTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .requestTimeoutSeconds) ?? 300
        defaultSystemPrompt = try container.decode(String.self, forKey: .defaultSystemPrompt)
    }

    static let `default` = GenerationSettings(
        provider: .localMock,
        endpoint: lmStudioDefaultEndpoint,
        apiKey: "",
        model: "gpt-4o-mini",
        temperature: 0.8,
        maxTokens: 700,
        enableStreaming: false,
        requestTimeoutSeconds: 300,
        defaultSystemPrompt: "You are a fiction writing assistant. Keep continuity and return only the generated passage."
    )
}

struct StoryProject: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var chapters: [Chapter]
    var compendium: [CompendiumEntry]
    var prompts: [PromptTemplate]
    var selectedProsePromptID: UUID?
    var selectedRewritePromptID: UUID?
    var selectedSummaryPromptID: UUID?
    var workshopSessions: [WorkshopSession]
    var selectedWorkshopSessionID: UUID?
    var selectedWorkshopPromptID: UUID?
    var sceneContextCompendiumSelection: [String: [UUID]]
    var settings: GenerationSettings
    var updatedAt: Date

    init(
        id: UUID,
        title: String,
        chapters: [Chapter],
        compendium: [CompendiumEntry],
        prompts: [PromptTemplate],
        selectedProsePromptID: UUID?,
        selectedRewritePromptID: UUID?,
        selectedSummaryPromptID: UUID?,
        workshopSessions: [WorkshopSession],
        selectedWorkshopSessionID: UUID?,
        selectedWorkshopPromptID: UUID?,
        sceneContextCompendiumSelection: [String: [UUID]],
        settings: GenerationSettings,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.chapters = chapters
        self.compendium = compendium
        self.prompts = prompts
        self.selectedProsePromptID = selectedProsePromptID
        self.selectedRewritePromptID = selectedRewritePromptID
        self.selectedSummaryPromptID = selectedSummaryPromptID
        self.workshopSessions = workshopSessions
        self.selectedWorkshopSessionID = selectedWorkshopSessionID
        self.selectedWorkshopPromptID = selectedWorkshopPromptID
        self.sceneContextCompendiumSelection = sceneContextCompendiumSelection
        self.settings = settings
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case chapters
        case compendium
        case prompts
        case selectedProsePromptID
        case selectedRewritePromptID
        case selectedSummaryPromptID
        case workshopSessions
        case selectedWorkshopSessionID
        case selectedWorkshopPromptID
        case sceneContextCompendiumSelection
        case settings
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        chapters = try container.decode([Chapter].self, forKey: .chapters)
        compendium = try container.decode([CompendiumEntry].self, forKey: .compendium)
        prompts = try container.decode([PromptTemplate].self, forKey: .prompts)
        selectedProsePromptID = try container.decodeIfPresent(UUID.self, forKey: .selectedProsePromptID)
        selectedRewritePromptID = try container.decodeIfPresent(UUID.self, forKey: .selectedRewritePromptID)
        selectedSummaryPromptID = try container.decodeIfPresent(UUID.self, forKey: .selectedSummaryPromptID)
        workshopSessions = try container.decodeIfPresent([WorkshopSession].self, forKey: .workshopSessions) ?? []
        selectedWorkshopSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedWorkshopSessionID)
        selectedWorkshopPromptID = try container.decodeIfPresent(UUID.self, forKey: .selectedWorkshopPromptID)
        sceneContextCompendiumSelection = try container.decodeIfPresent([String: [UUID]].self, forKey: .sceneContextCompendiumSelection) ?? [:]
        settings = try container.decode(GenerationSettings.self, forKey: .settings)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    static func starter() -> StoryProject {
        let firstScene = Scene(
            title: "Scene 1",
            content: "Rain hammered the station roof while Mara watched the empty platform."
        )
        let firstChapter = Chapter(title: "Chapter 1", scenes: [firstScene])

        let compendium: [CompendiumEntry] = [
            CompendiumEntry(
                category: .characters,
                title: "Mara Voss",
                body: "Smuggler turned courier. Sharp, suspicious, and stubbornly loyal.",
                tags: ["protagonist", "courier"]
            ),
            CompendiumEntry(
                category: .locations,
                title: "North Platform",
                body: "An old transit platform with intermittent power and poor surveillance.",
                tags: ["station"]
            )
        ]

        let defaultPrompt = PromptTemplate.defaultProseTemplate
        let defaultRewritePrompt = PromptTemplate(
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
        let defaultSummaryPrompt = PromptTemplate(
            category: .summary,
            title: "Summary",
            userTemplate: """
            Summarize this scene with focus on key events, intent, character motivation, and unresolved threads.

            CURRENT SCENE:
            {scene}

            CONTEXT:
            {context}

            Return only the summary text.
            """,
            systemTemplate: "You summarize fiction drafts with accurate details and continuity awareness."
        )
        let defaultWorkshopPrompt = PromptTemplate.defaultWorkshopTemplate

        let workshopSession = WorkshopSession(
            name: "Chat 1",
            messages: [
                WorkshopMessage(
                    role: .assistant,
                    content: "I’m ready to workshop your story. Ask for brainstorming, line edits, continuity checks, or scene alternatives."
                )
            ]
        )

        return StoryProject(
            id: UUID(),
            title: "Untitled Project",
            chapters: [firstChapter],
            compendium: compendium,
            prompts: [defaultPrompt, defaultRewritePrompt, defaultSummaryPrompt, defaultWorkshopPrompt],
            selectedProsePromptID: defaultPrompt.id,
            selectedRewritePromptID: defaultRewritePrompt.id,
            selectedSummaryPromptID: defaultSummaryPrompt.id,
            workshopSessions: [workshopSession],
            selectedWorkshopSessionID: workshopSession.id,
            selectedWorkshopPromptID: defaultWorkshopPrompt.id,
            sceneContextCompendiumSelection: [:],
            settings: .default,
            updatedAt: .now
        )
    }
}
