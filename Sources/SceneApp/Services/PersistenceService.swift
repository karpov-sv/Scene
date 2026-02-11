import Foundation

@MainActor
final class ProjectPersistence {
    static let shared = ProjectPersistence()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> StoryProject? {
        let fileURL = try makeFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(StoryProject.self, from: data)
    }

    func save(_ project: StoryProject) throws {
        let fileURL = try makeFileURL()
        let data = try encoder.encode(project)
        try data.write(to: fileURL, options: .atomic)
    }

    private func makeFileURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appFolder = appSupport.appendingPathComponent("SceneApp", isDirectory: true)

        if !fileManager.fileExists(atPath: appFolder.path) {
            try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }

        return appFolder.appendingPathComponent("project.json", isDirectory: false)
    }
}
