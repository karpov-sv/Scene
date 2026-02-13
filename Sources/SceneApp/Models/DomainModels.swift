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
    case openAI
    case anthropic
    case openRouter
    case lmStudio
    case openAICompatible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI:
            return "OpenAI (ChatGPT)"
        case .anthropic:
            return "Anthropic (Claude)"
        case .openRouter:
            return "OpenRouter"
        case .lmStudio:
            return "LM Studio (Local)"
        case .openAICompatible:
            return "OpenAI-Compatible (Custom)"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openAI:
            return GenerationSettings.openAIDefaultEndpoint
        case .anthropic:
            return GenerationSettings.anthropicDefaultEndpoint
        case .openRouter:
            return GenerationSettings.openRouterDefaultEndpoint
        case .lmStudio, .openAICompatible:
            return GenerationSettings.lmStudioDefaultEndpoint
        }
    }

    var usesOpenAICompatibleAPI: Bool {
        switch self {
        case .anthropic:
            return false
        case .openAI, .openRouter, .lmStudio, .openAICompatible:
            return true
        }
    }

    var supportsModelDiscovery: Bool {
        true
    }

    var supportsStreaming: Bool {
        true
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        if let provider = AIProvider(rawValue: raw) {
            self = provider
            return
        }

        // Migrate legacy values from previous builds.
        switch raw {
        case "localMock":
            self = .lmStudio
        case "openAICompatible":
            self = .openAICompatible
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown AI provider value: \(raw)"
            )
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

    static let cinematicProseID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let rewriteID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    static let expandID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    static let shortenID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
    static let summaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    static let workshopID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!

    static let defaultProseTemplate = PromptTemplate(
        id: cinematicProseID,
        title: "Cinematic Prose",
        userTemplate: """
        Continue this scene from the provided beat.

        PROJECT:
        {{project_title}}

        CHAPTER:
        {{chapter_title}}

        SCENE:
        {{scene_title}}

        BEAT:
        {{beat}}

        CURRENT SCENE (RECENT EXCERPT):
        {{scene_tail(chars=4500)}}

        CONTEXT:
        {{context}}

        Requirements:
        - Continue only the immediate next passage.
        - Preserve POV, tense, and voice consistency.
        - Avoid tidy scene conclusions unless explicitly requested.

        Return only the generated prose passage.
        """,
        systemTemplate: "You are an expert fiction writing assistant. Preserve continuity, character voice, and factual consistency. Show, do not tell. Avoid cliche phrasing. Return prose only."
    )

    static let defaultRewriteTemplate = PromptTemplate(
        id: rewriteID,
        category: .rewrite,
        title: "Rewrite",
        userTemplate: """
        Rewrite the selected passage while preserving its intent and continuity.

        CHAPTER:
        {{chapter_title}}

        SCENE:
        {{scene_title}}

        SELECTED PASSAGE:
        {{selection}}

        CURRENT SCENE (RECENT EXCERPT):
        {{scene_tail(chars=4500)}}

        CONTEXT:
        {{context}}

        Requirements:
        - Keep meaning, tone, and narrative intent.
        - Maintain POV and tense.
        - Improve flow, clarity, and natural phrasing.

        Return only the rewritten passage.
        """,
        systemTemplate: "You are a fiction editing assistant. Preserve intent and continuity while improving readability and style. Return only the rewritten passage."
    )

    static let defaultExpandTemplate = PromptTemplate(
        id: expandID,
        category: .rewrite,
        title: "Expand",
        userTemplate: """
        Expand the selected passage with richer detail while staying consistent with the scene.

        CHAPTER:
        {{chapter_title}}

        SCENE:
        {{scene_title}}

        SELECTED PASSAGE:
        {{selection}}

        CURRENT SCENE (RECENT EXCERPT):
        {{scene_tail(chars=4500)}}

        CONTEXT:
        {{context}}

        Requirements:
        - Keep original meaning and chronology.
        - Add sensory detail, emotional texture, and specific action.
        - Preserve POV, tense, and tone.

        Return only the expanded passage.
        """,
        systemTemplate: "You are a fiction editing assistant specializing in expansion. Add detail and texture without changing narrative intent or continuity."
    )

    static let defaultShortenTemplate = PromptTemplate(
        id: shortenID,
        category: .rewrite,
        title: "Shorten",
        userTemplate: """
        Shorten the selected passage while preserving key meaning and tone.

        CHAPTER:
        {{chapter_title}}

        SCENE:
        {{scene_title}}

        SELECTED PASSAGE:
        {{selection}}

        CURRENT SCENE (RECENT EXCERPT):
        {{scene_tail(chars=4500)}}

        CONTEXT:
        {{context}}

        Requirements:
        - Keep essential events and implications.
        - Remove repetition, filler, and non-essential wording.
        - Preserve POV, tense, and continuity.

        Return only the shortened passage.
        """,
        systemTemplate: "You are a fiction editing assistant specializing in concise prose. Compress text without losing essential meaning or continuity."
    )

    static let defaultSummaryTemplate = PromptTemplate(
        id: summaryID,
        category: .summary,
        title: "Summary",
        userTemplate: """
        Create a concise narrative summary from the source material.

        SCOPE:
        {{summary_scope}}

        CHAPTER:
        {{chapter_title}}

        SCENE:
        {{scene_title}}

        SOURCE MATERIAL:
        {{source}}

        SUPPORTING CONTEXT:
        {{context}}

        Requirements:
        - Use third-person narrative.
        - Keep chronology and causality clear.
        - Cover key events, character decisions, and unresolved threads.
        - Do not invent facts that are not present in the source/context.

        Return only the summary text.
        """,
        systemTemplate: "You summarize fiction drafts accurately and concisely. Preserve continuity, avoid hallucinations, and return plain summary prose only."
    )

    static let defaultWorkshopTemplate = PromptTemplate(
        id: workshopID,
        category: .workshop,
        title: "Story Workshop",
        userTemplate: """
        Work with me on this story problem.

        CHAT:
        {{chat_name}}

        CONTEXT:
        {{context}}

        CURRENT SCENE:
        {{scene_tail(chars=2400)}}

        CONVERSATION:
        {{chat_history(turns=14)}}
        """,
        systemTemplate: "You are an experienced writing coach helping the user improve scenes, pacing, structure, and character work. Be practical and specific."
    )

    static var builtInTemplates: [PromptTemplate] {
        [
            defaultProseTemplate,
            defaultRewriteTemplate,
            defaultExpandTemplate,
            defaultShortenTemplate,
            defaultSummaryTemplate,
            defaultWorkshopTemplate,
        ]
    }
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
    var generationModelSelection: [String]
    var useInlineGeneration: Bool
    var temperature: Double
    var maxTokens: Int
    var enableStreaming: Bool
    var requestTimeoutSeconds: Double
    var defaultSystemPrompt: String

    static let openAIDefaultEndpoint = "https://api.openai.com/v1"
    static let anthropicDefaultEndpoint = "https://api.anthropic.com"
    static let openRouterDefaultEndpoint = "https://openrouter.ai/api/v1"
    static let lmStudioDefaultEndpoint = "http://localhost:1234/v1"
    static let ollamaDefaultEndpoint = "http://localhost:11434/v1"

    init(
        provider: AIProvider,
        endpoint: String,
        apiKey: String,
        model: String,
        generationModelSelection: [String],
        useInlineGeneration: Bool,
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
        self.generationModelSelection = generationModelSelection
        self.useInlineGeneration = useInlineGeneration
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
        case generationModelSelection
        case useInlineGeneration
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
        let decodedSelection = try container.decodeIfPresent([String].self, forKey: .generationModelSelection) ?? []
        let normalizedSelection = decodedSelection
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if normalizedSelection.isEmpty {
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            generationModelSelection = trimmedModel.isEmpty ? [] : [trimmedModel]
        } else {
            var deduplicated: [String] = []
            var seen = Set<String>()
            for entry in normalizedSelection where seen.insert(entry).inserted {
                deduplicated.append(entry)
            }
            generationModelSelection = deduplicated
        }
        useInlineGeneration = try container.decodeIfPresent(Bool.self, forKey: .useInlineGeneration) ?? false
        temperature = try container.decode(Double.self, forKey: .temperature)
        maxTokens = try container.decode(Int.self, forKey: .maxTokens)
        enableStreaming = try container.decodeIfPresent(Bool.self, forKey: .enableStreaming) ?? true
        requestTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .requestTimeoutSeconds) ?? 300
        defaultSystemPrompt = try container.decode(String.self, forKey: .defaultSystemPrompt)
    }

    static let `default` = GenerationSettings(
        provider: .openAI,
        endpoint: openAIDefaultEndpoint,
        apiKey: "",
        model: "gpt-4o-mini",
        generationModelSelection: ["gpt-4o-mini"],
        useInlineGeneration: false,
        temperature: 0.8,
        maxTokens: 700,
        enableStreaming: true,
        requestTimeoutSeconds: 300,
        defaultSystemPrompt: "You are a fiction writing assistant. Keep continuity and return only the generated passage."
    )
}

struct StoryProject: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var autosaveEnabled: Bool
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
    var sceneContextSceneSummarySelection: [String: [UUID]]
    var sceneContextChapterSummarySelection: [String: [UUID]]
    var settings: GenerationSettings
    var updatedAt: Date

    init(
        id: UUID,
        title: String,
        autosaveEnabled: Bool,
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
        sceneContextSceneSummarySelection: [String: [UUID]],
        sceneContextChapterSummarySelection: [String: [UUID]],
        settings: GenerationSettings,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.autosaveEnabled = autosaveEnabled
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
        self.sceneContextSceneSummarySelection = sceneContextSceneSummarySelection
        self.sceneContextChapterSummarySelection = sceneContextChapterSummarySelection
        self.settings = settings
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case autosaveEnabled
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
        case sceneContextSceneSummarySelection
        case sceneContextChapterSummarySelection
        case settings
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        autosaveEnabled = try container.decodeIfPresent(Bool.self, forKey: .autosaveEnabled) ?? true
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
        sceneContextSceneSummarySelection = try container.decodeIfPresent([String: [UUID]].self, forKey: .sceneContextSceneSummarySelection) ?? [:]
        sceneContextChapterSummarySelection = try container.decodeIfPresent([String: [UUID]].self, forKey: .sceneContextChapterSummarySelection) ?? [:]
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
            autosaveEnabled: true,
            chapters: [firstChapter],
            compendium: compendium,
            prompts: PromptTemplate.builtInTemplates,
            selectedProsePromptID: PromptTemplate.defaultProseTemplate.id,
            selectedRewritePromptID: PromptTemplate.defaultRewriteTemplate.id,
            selectedSummaryPromptID: PromptTemplate.defaultSummaryTemplate.id,
            workshopSessions: [workshopSession],
            selectedWorkshopSessionID: workshopSession.id,
            selectedWorkshopPromptID: PromptTemplate.defaultWorkshopTemplate.id,
            sceneContextCompendiumSelection: [:],
            sceneContextSceneSummarySelection: [:],
            sceneContextChapterSummarySelection: [:],
            settings: .default,
            updatedAt: .now
        )
    }
}
