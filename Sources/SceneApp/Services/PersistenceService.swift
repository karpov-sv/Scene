import Foundation

enum ProjectPersistenceError: LocalizedError {
    case projectNotFound
    case projectAlreadyExists
    case invalidProjectLocation
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier(String)
    case missingReference(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "Project folder was not found."
        case .projectAlreadyExists:
            return "A project already exists at the selected location."
        case .invalidProjectLocation:
            return "Selected location is not a valid Scene project."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported project schema version \(version)."
        case .duplicateIdentifier(let details):
            return "Project contains duplicate identifiers (\(details))."
        case .missingReference(let details):
            return "Project is missing referenced data (\(details))."
        }
    }
}

final class ProjectPersistence {
    nonisolated(unsafe) static let shared = ProjectPersistence()

    nonisolated static let projectDirectoryExtension = "sceneproj"

    private static let manifestFileName = "manifest.json"
    private static let schemaVersion = 1
    private static let checkpointEnvelopeVersion = "1.0"
    private static let checkpointEnvelopeType = "scene-project-checkpoint"
    static let checkpointsDirectoryName = "checkpoints"
    private static let checkpointFilenamePrefix = "checkpoint-"
    private static let lastOpenedProjectPathKey = "SceneApp.lastOpenedProjectPath"
    private static let lastOpenedProjectPathsKey = "SceneApp.lastOpenedProjectPaths"

    struct ProjectCheckpoint: Identifiable, Equatable {
        var id: String { fileName }
        let fileName: String
        let createdAt: Date
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let userDefaults: UserDefaults

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = UserDefaults(suiteName: "com.karpov.SceneApp") ?? .standard
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    private struct ProjectCheckpointEnvelope: Codable {
        var version: String
        var type: String
        var createdAt: Date
        var project: StoryProject
    }

    func normalizeProjectURL(_ proposedURL: URL) -> URL {
        let standardized = proposedURL.standardizedFileURL
        if standardized.pathExtension.lowercased() == Self.projectDirectoryExtension {
            return standardized
        }
        return standardized.appendingPathExtension(Self.projectDirectoryExtension)
    }

    func resolveExistingProjectURL(_ proposedURL: URL) throws -> URL {
        let standardized = proposedURL.standardizedFileURL
        let manifestAtProposed = standardized.appendingPathComponent(Self.manifestFileName)

        if fileManager.fileExists(atPath: manifestAtProposed.path) {
            return standardized
        }

        let normalized = normalizeProjectURL(standardized)
        let manifestAtNormalized = normalized.appendingPathComponent(Self.manifestFileName)
        if fileManager.fileExists(atPath: manifestAtNormalized.path) {
            return normalized
        }

        throw ProjectPersistenceError.projectNotFound
    }

    @discardableResult
    func createProject(_ project: StoryProject, at proposedURL: URL) throws -> URL {
        let projectURL = normalizeProjectURL(proposedURL)
        if fileManager.fileExists(atPath: projectURL.path) {
            throw ProjectPersistenceError.projectAlreadyExists
        }

        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try markAsPackage(projectURL)
        try writeProject(project, at: projectURL)
        return projectURL
    }

    func loadProject(at proposedURL: URL) throws -> StoryProject {
        let projectURL = try resolveExistingProjectURL(proposedURL)
        return try readProject(at: projectURL)
    }

    @discardableResult
    func saveProject(_ project: StoryProject, at proposedURL: URL) throws -> URL {
        let projectURL = normalizeProjectURL(proposedURL)

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: projectURL.path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                throw ProjectPersistenceError.invalidProjectLocation
            }
        } else {
            try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        }

        try markAsPackage(projectURL)
        try writeProject(project, at: projectURL)
        return projectURL
    }

    @discardableResult
    func duplicateProject(from sourceURL: URL, to destinationURL: URL) throws -> URL {
        let sourceProjectURL = try resolveExistingProjectURL(sourceURL)
        let destinationProjectURL = normalizeProjectURL(destinationURL)

        if fileManager.fileExists(atPath: destinationProjectURL.path) {
            throw ProjectPersistenceError.projectAlreadyExists
        }

        try fileManager.copyItem(at: sourceProjectURL, to: destinationProjectURL)
        try markAsPackage(destinationProjectURL)
        return destinationProjectURL
    }

    func loadLastOpenedProjectURL() -> URL? {
        guard let path = userDefaults.string(forKey: Self.lastOpenedProjectPathKey) else {
            return nil
        }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        let manifestURL = url.appendingPathComponent(Self.manifestFileName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            clearLastOpenedProjectURL()
            return nil
        }

        return url
    }

    func loadLastOpenedProjectURLs() -> [URL] {
        guard let paths = userDefaults.array(forKey: Self.lastOpenedProjectPathsKey) as? [String] else {
            return []
        }

        var seen = Set<String>()
        var validURLs: [URL] = []

        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard seen.insert(url.path).inserted else { continue }

            let manifestURL = url.appendingPathComponent(Self.manifestFileName)
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

            validURLs.append(url)
        }

        if validURLs.isEmpty {
            userDefaults.removeObject(forKey: Self.lastOpenedProjectPathsKey)
            return []
        }

        if validURLs.map(\.path) != paths {
            saveLastOpenedProjectURLs(validURLs)
        }

        return validURLs
    }

    func saveLastOpenedProjectURL(_ projectURL: URL) {
        let normalizedURL = projectURL.standardizedFileURL
        var urls = loadLastOpenedProjectURLs()
        urls.removeAll { $0.standardizedFileURL == normalizedURL }
        urls.insert(normalizedURL, at: 0)

        if urls.count > 24 {
            urls.removeSubrange(24..<urls.count)
        }

        saveLastOpenedProjectURLs(urls)
    }

    func saveLastOpenedProjectURLs(_ projectURLs: [URL]) {
        var seen = Set<String>()
        let normalizedPaths = projectURLs
            .map(\.standardizedFileURL)
            .filter { seen.insert($0.path).inserted }
            .map(\.path)

        if normalizedPaths.isEmpty {
            clearLastOpenedProjectURL()
            return
        }

        userDefaults.set(normalizedPaths, forKey: Self.lastOpenedProjectPathsKey)
        userDefaults.set(normalizedPaths[0], forKey: Self.lastOpenedProjectPathKey)
    }

    func clearLastOpenedProjectURL() {
        userDefaults.removeObject(forKey: Self.lastOpenedProjectPathKey)
        userDefaults.removeObject(forKey: Self.lastOpenedProjectPathsKey)
    }

    // MARK: - Checkpoints

    @discardableResult
    func createCheckpoint(for project: StoryProject, at proposedURL: URL) throws -> ProjectCheckpoint {
        let projectURL = try resolveExistingProjectURL(proposedURL)
        let checkpointsURL = projectURL.appendingPathComponent(Self.checkpointsDirectoryName, isDirectory: true)
        try ensureDirectoryExists(checkpointsURL)

        let createdAt = Date()
        var fileName = Self.checkpointFilenamePrefix + checkpointFileTimestamp(from: createdAt) + ".json"
        var destinationURL = checkpointsURL.appendingPathComponent(fileName, isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path) {
            let suffix = String(UUID().uuidString.prefix(8))
            fileName = Self.checkpointFilenamePrefix + checkpointFileTimestamp(from: createdAt) + "-\(suffix).json"
            destinationURL = checkpointsURL.appendingPathComponent(fileName, isDirectory: false)
        }

        let envelope = ProjectCheckpointEnvelope(
            version: Self.checkpointEnvelopeVersion,
            type: Self.checkpointEnvelopeType,
            createdAt: createdAt,
            project: project
        )

        let data = try encoder.encode(envelope)
        try data.write(to: destinationURL, options: .atomic)

        return ProjectCheckpoint(fileName: fileName, createdAt: createdAt)
    }

    func listCheckpoints(at proposedURL: URL) throws -> [ProjectCheckpoint] {
        let projectURL = try resolveExistingProjectURL(proposedURL)
        let checkpointsURL = projectURL.appendingPathComponent(Self.checkpointsDirectoryName, isDirectory: true)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: checkpointsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: checkpointsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var checkpoints: [ProjectCheckpoint] = []
        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "json" {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }

            guard let data = try? Data(contentsOf: fileURL),
                  let envelope = try? decoder.decode(ProjectCheckpointEnvelope.self, from: data),
                  envelope.type == Self.checkpointEnvelopeType else {
                continue
            }

            checkpoints.append(
                ProjectCheckpoint(
                    fileName: fileURL.lastPathComponent,
                    createdAt: envelope.createdAt
                )
            )
        }

        checkpoints.sort { $0.createdAt > $1.createdAt }
        return checkpoints
    }

    func loadCheckpoint(at proposedURL: URL, fileName: String) throws -> StoryProject {
        let projectURL = try resolveExistingProjectURL(proposedURL)
        let checkpointsURL = projectURL.appendingPathComponent(Self.checkpointsDirectoryName, isDirectory: true)

        let sanitizedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedName.isEmpty,
              !sanitizedName.contains("/"),
              !sanitizedName.contains(":") else {
            throw ProjectPersistenceError.invalidProjectLocation
        }

        let checkpointURL = checkpointsURL.appendingPathComponent(sanitizedName, isDirectory: false)
        guard fileManager.fileExists(atPath: checkpointURL.path) else {
            throw ProjectPersistenceError.missingReference(sanitizedName)
        }

        let data = try Data(contentsOf: checkpointURL)
        let envelope = try decoder.decode(ProjectCheckpointEnvelope.self, from: data)
        guard envelope.type == Self.checkpointEnvelopeType else {
            throw ProjectPersistenceError.invalidProjectLocation
        }

        return envelope.project
    }

    func loadProject(from fileWrapper: FileWrapper) throws -> StoryProject {
        try withTemporaryProjectDirectory(named: "Imported.sceneproj") { projectURL in
            try fileWrapper.write(to: projectURL, options: .atomic, originalContentsURL: nil)
            return try loadProject(at: projectURL)
        }
    }

    func makeFileWrapper(for project: StoryProject) throws -> FileWrapper {
        try withTemporaryProjectDirectory(named: "Exported.sceneproj") { projectURL in
            _ = try saveProject(project, at: projectURL)
            return try FileWrapper(url: projectURL, options: .immediate)
        }
    }

    // MARK: - File Layout

    private struct ProjectManifest: Codable {
        var schemaVersion: Int
        var id: UUID
        var title: String
        var notes: String?
        var autosaveEnabled: Bool?
        var updatedAt: Date
        var selectedSceneID: UUID?
        var selectedProsePromptID: UUID?
        var selectedRewritePromptID: UUID?
        var selectedSummaryPromptID: UUID?
        var selectedWorkshopSessionID: UUID?
        var workshopInputHistoryBySession: [String: [String]]?
        var selectedWorkshopPromptID: UUID?
        var beatInputHistoryByScene: [String: [String]]?
        var sceneContextCompendiumSelection: [String: [UUID]]
        var sceneContextSceneSummarySelection: [String: [UUID]]?
        var sceneContextChapterSummarySelection: [String: [UUID]]?
        var sceneNarrativeStates: [String: SceneNarrativeState]?
        var settings: GenerationSettings
        var editorAppearance: EditorAppearanceSettings?
        var chapters: [ChapterRecord]
        var scenes: [SceneRecord]
        var compendium: [CompendiumRecord]
        var prompts: [PromptRecord]
        var workshopSessions: [WorkshopSessionRecord]
    }

    private struct ChapterRecord: Codable {
        var id: UUID
        var title: String
        var updatedAt: Date
        var sceneIDs: [UUID]
        var summary: String
        var notes: String

        private enum CodingKeys: String, CodingKey {
            case id
            case title
            case updatedAt
            case sceneIDs
            case summary
            case notes
        }

        init(id: UUID, title: String, updatedAt: Date, sceneIDs: [UUID], summary: String, notes: String) {
            self.id = id
            self.title = title
            self.updatedAt = updatedAt
            self.sceneIDs = sceneIDs
            self.summary = summary
            self.notes = notes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            sceneIDs = try container.decode([UUID].self, forKey: .sceneIDs)
            summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
            notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        }
    }

    private struct SceneRecord: Codable {
        var id: UUID
        var title: String
        var updatedAt: Date
        var contentPath: String
        var summary: String
        var notes: String

        private enum CodingKeys: String, CodingKey {
            case id
            case title
            case updatedAt
            case contentPath
            case summary
            case notes
        }

        init(id: UUID, title: String, updatedAt: Date, contentPath: String, summary: String, notes: String) {
            self.id = id
            self.title = title
            self.updatedAt = updatedAt
            self.contentPath = contentPath
            self.summary = summary
            self.notes = notes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            contentPath = try container.decode(String.self, forKey: .contentPath)
            summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
            notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        }
    }

    private struct CompendiumRecord: Codable {
        var id: UUID
        var category: CompendiumCategory
        var title: String
        var tags: [String]
        var updatedAt: Date
        var bodyPath: String
    }

    private struct PromptRecord: Codable {
        var id: UUID
        var category: PromptCategory
        var title: String
        var userTemplate: String
        var systemTemplate: String
    }

    private struct WorkshopSessionRecord: Codable {
        var id: UUID
        var name: String
        var updatedAt: Date
        var messagesPath: String
    }

    private enum Layout {
        static let scenesFolder = "scenes"
        static let compendiumFolder = "compendium"
        static let workshopFolder = "workshop"
    }

    private func withTemporaryProjectDirectory<T>(
        named name: String,
        _ body: (URL) throws -> T
    ) throws -> T {
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("SceneDoc-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let projectURL = baseURL.appendingPathComponent(name, isDirectory: true)

        defer {
            try? fileManager.removeItem(at: baseURL)
        }

        return try body(projectURL)
    }

    private func markAsPackage(_ projectURL: URL) throws {
        var values = URLResourceValues()
        values.isPackage = true
        var mutableURL = projectURL
        try mutableURL.setResourceValues(values)
    }

    // MARK: - Read

    private func readProject(at projectURL: URL) throws -> StoryProject {
        let manifestURL = projectURL.appendingPathComponent(Self.manifestFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw ProjectPersistenceError.invalidProjectLocation
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(ProjectManifest.self, from: manifestData)

        guard manifest.schemaVersion == Self.schemaVersion else {
            throw ProjectPersistenceError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        var sceneByID: [UUID: Scene] = [:]
        for record in manifest.scenes {
            if sceneByID[record.id] != nil {
                throw ProjectPersistenceError.duplicateIdentifier("scene \(record.id.uuidString)")
            }

            let (content, contentRTFData) = try readSceneContent(
                at: projectURL.appendingPathComponent(record.contentPath, isDirectory: false)
            )
            sceneByID[record.id] = Scene(
                id: record.id,
                title: record.title,
                content: content,
                contentRTFData: contentRTFData,
                summary: record.summary,
                notes: record.notes,
                updatedAt: record.updatedAt
            )
        }

        let chapters: [Chapter] = try manifest.chapters.map { record in
            let scenes = try record.sceneIDs.map { sceneID in
                guard let scene = sceneByID[sceneID] else {
                    throw ProjectPersistenceError.missingReference("scene \(sceneID.uuidString)")
                }
                return scene
            }

            return Chapter(
                id: record.id,
                title: record.title,
                scenes: scenes,
                summary: record.summary,
                notes: record.notes,
                updatedAt: record.updatedAt
            )
        }

        var entryIDs = Set<UUID>()
        let compendium: [CompendiumEntry] = try manifest.compendium.map { record in
            if !entryIDs.insert(record.id).inserted {
                throw ProjectPersistenceError.duplicateIdentifier("compendium entry \(record.id.uuidString)")
            }

            let body = try readText(at: projectURL.appendingPathComponent(record.bodyPath, isDirectory: false))
            return CompendiumEntry(
                id: record.id,
                category: record.category,
                title: record.title,
                body: body,
                tags: record.tags,
                updatedAt: record.updatedAt
            )
        }

        var promptIDs = Set<UUID>()
        let prompts: [PromptTemplate] = try manifest.prompts.map { record in
            if !promptIDs.insert(record.id).inserted {
                throw ProjectPersistenceError.duplicateIdentifier("prompt \(record.id.uuidString)")
            }

            return PromptTemplate(
                id: record.id,
                category: record.category,
                title: record.title,
                userTemplate: record.userTemplate,
                systemTemplate: record.systemTemplate
            )
        }

        var sessionIDs = Set<UUID>()
        let workshopSessions: [WorkshopSession] = try manifest.workshopSessions.map { record in
            if !sessionIDs.insert(record.id).inserted {
                throw ProjectPersistenceError.duplicateIdentifier("workshop session \(record.id.uuidString)")
            }

            let messagesURL = projectURL.appendingPathComponent(record.messagesPath, isDirectory: false)
            let messageData = try Data(contentsOf: messagesURL)
            let messages = try decoder.decode([WorkshopMessage].self, from: messageData)

            return WorkshopSession(
                id: record.id,
                name: record.name,
                messages: messages,
                updatedAt: record.updatedAt
            )
        }

        return StoryProject(
            id: manifest.id,
            title: manifest.title,
            notes: manifest.notes ?? "",
            autosaveEnabled: manifest.autosaveEnabled ?? true,
            chapters: chapters,
            compendium: compendium,
            prompts: prompts,
            selectedSceneID: manifest.selectedSceneID,
            selectedProsePromptID: manifest.selectedProsePromptID,
            selectedRewritePromptID: manifest.selectedRewritePromptID,
            selectedSummaryPromptID: manifest.selectedSummaryPromptID,
            workshopSessions: workshopSessions,
            selectedWorkshopSessionID: manifest.selectedWorkshopSessionID,
            workshopInputHistoryBySession: manifest.workshopInputHistoryBySession ?? [:],
            selectedWorkshopPromptID: manifest.selectedWorkshopPromptID,
            beatInputHistoryByScene: manifest.beatInputHistoryByScene ?? [:],
            sceneContextCompendiumSelection: manifest.sceneContextCompendiumSelection,
            sceneContextSceneSummarySelection: manifest.sceneContextSceneSummarySelection ?? [:],
            sceneContextChapterSummarySelection: manifest.sceneContextChapterSummarySelection ?? [:],
            sceneNarrativeStates: manifest.sceneNarrativeStates ?? [:],
            settings: manifest.settings,
            editorAppearance: manifest.editorAppearance ?? .default,
            updatedAt: manifest.updatedAt
        )
    }

    // MARK: - Write

    private func writeProject(_ project: StoryProject, at projectURL: URL) throws {
        let scenesFolder = projectURL.appendingPathComponent(Layout.scenesFolder, isDirectory: true)
        let compendiumFolder = projectURL.appendingPathComponent(Layout.compendiumFolder, isDirectory: true)
        let workshopFolder = projectURL.appendingPathComponent(Layout.workshopFolder, isDirectory: true)

        try ensureDirectoryExists(scenesFolder)
        try ensureDirectoryExists(compendiumFolder)
        try ensureDirectoryExists(workshopFolder)

        var seenSceneIDs = Set<UUID>()
        var sceneRecords: [SceneRecord] = []
        for chapter in project.chapters {
            for scene in chapter.scenes {
                if !seenSceneIDs.insert(scene.id).inserted {
                    throw ProjectPersistenceError.duplicateIdentifier("scene \(scene.id.uuidString)")
                }

                let filename = "\(scene.id.uuidString).rtf"
                let contentPath = "\(Layout.scenesFolder)/\(filename)"
                let contentURL = scenesFolder.appendingPathComponent(filename, isDirectory: false)
                try writeSceneContent(
                    text: scene.content,
                    richTextData: scene.contentRTFData,
                    to: contentURL
                )

                sceneRecords.append(
                    SceneRecord(
                        id: scene.id,
                        title: scene.title,
                        updatedAt: scene.updatedAt,
                        contentPath: contentPath,
                        summary: scene.summary,
                        notes: scene.notes
                    )
                )
            }
        }

        var seenCompendiumIDs = Set<UUID>()
        let compendiumRecords: [CompendiumRecord] = try project.compendium.map { entry in
            if !seenCompendiumIDs.insert(entry.id).inserted {
                throw ProjectPersistenceError.duplicateIdentifier("compendium entry \(entry.id.uuidString)")
            }

            let filename = "\(entry.id.uuidString).md"
            let bodyPath = "\(Layout.compendiumFolder)/\(filename)"
            let bodyURL = compendiumFolder.appendingPathComponent(filename, isDirectory: false)
            try writeText(entry.body, to: bodyURL)

            return CompendiumRecord(
                id: entry.id,
                category: entry.category,
                title: entry.title,
                tags: entry.tags,
                updatedAt: entry.updatedAt,
                bodyPath: bodyPath
            )
        }

        var seenPromptIDs = Set<UUID>()
        let promptRecords: [PromptRecord] = try project.prompts.map { prompt in
            if !seenPromptIDs.insert(prompt.id).inserted {
                throw ProjectPersistenceError.duplicateIdentifier("prompt \(prompt.id.uuidString)")
            }

            return PromptRecord(
                id: prompt.id,
                category: prompt.category,
                title: prompt.title,
                userTemplate: prompt.userTemplate,
                systemTemplate: prompt.systemTemplate
            )
        }

        var seenSessionIDs = Set<UUID>()
        let workshopSessionRecords: [WorkshopSessionRecord] = try project.workshopSessions.map { session in
            if !seenSessionIDs.insert(session.id).inserted {
                throw ProjectPersistenceError.duplicateIdentifier("workshop session \(session.id.uuidString)")
            }

            let filename = "\(session.id.uuidString).json"
            let messagesPath = "\(Layout.workshopFolder)/\(filename)"
            let messagesURL = workshopFolder.appendingPathComponent(filename, isDirectory: false)
            let messageData = try encoder.encode(session.messages)
            try messageData.write(to: messagesURL, options: .atomic)

            return WorkshopSessionRecord(
                id: session.id,
                name: session.name,
                updatedAt: session.updatedAt,
                messagesPath: messagesPath
            )
        }

        let chapterRecords = project.chapters.map { chapter in
            ChapterRecord(
                id: chapter.id,
                title: chapter.title,
                updatedAt: chapter.updatedAt,
                sceneIDs: chapter.scenes.map(\.id),
                summary: chapter.summary,
                notes: chapter.notes
            )
        }

        let manifest = ProjectManifest(
            schemaVersion: Self.schemaVersion,
            id: project.id,
            title: project.title,
            notes: project.notes,
            autosaveEnabled: project.autosaveEnabled,
            updatedAt: project.updatedAt,
            selectedSceneID: project.selectedSceneID,
            selectedProsePromptID: project.selectedProsePromptID,
            selectedRewritePromptID: project.selectedRewritePromptID,
            selectedSummaryPromptID: project.selectedSummaryPromptID,
            selectedWorkshopSessionID: project.selectedWorkshopSessionID,
            workshopInputHistoryBySession: project.workshopInputHistoryBySession,
            selectedWorkshopPromptID: project.selectedWorkshopPromptID,
            beatInputHistoryByScene: project.beatInputHistoryByScene,
            sceneContextCompendiumSelection: project.sceneContextCompendiumSelection,
            sceneContextSceneSummarySelection: project.sceneContextSceneSummarySelection,
            sceneContextChapterSummarySelection: project.sceneContextChapterSummarySelection,
            sceneNarrativeStates: project.sceneNarrativeStates,
            settings: project.settings,
            editorAppearance: project.editorAppearance,
            chapters: chapterRecords,
            scenes: sceneRecords,
            compendium: compendiumRecords,
            prompts: promptRecords,
            workshopSessions: workshopSessionRecords
        )

        let manifestURL = projectURL.appendingPathComponent(Self.manifestFileName, isDirectory: false)
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)
    }

    // MARK: - IO Helpers

    private func ensureDirectoryExists(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return
            }
            throw ProjectPersistenceError.invalidProjectLocation
        }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func readText(at url: URL) throws -> String {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ProjectPersistenceError.missingReference(url.lastPathComponent)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func writeText(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        try data.write(to: url, options: .atomic)
    }

    private func readSceneContent(at url: URL) throws -> (String, Data?) {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ProjectPersistenceError.missingReference(url.lastPathComponent)
        }

        let data = try Data(contentsOf: url)
        if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            return (attributed.string, data)
        }

        if let text = String(data: data, encoding: .utf8) {
            return (text, nil)
        }

        throw ProjectPersistenceError.invalidProjectLocation
    }

    private func writeSceneContent(text: String, richTextData: Data?, to url: URL) throws {
        if let richTextData {
            try richTextData.write(to: url, options: .atomic)
            return
        }

        let attributed = NSAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)
        let rtfData = try attributed.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try rtfData.write(to: url, options: .atomic)
    }

    private func checkpointFileTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
