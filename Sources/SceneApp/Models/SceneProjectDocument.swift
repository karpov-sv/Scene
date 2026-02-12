import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

extension UTType {
    static var sceneProject: UTType {
        UTType(exportedAs: "com.karpov.scene.project")
    }
}

@preconcurrency
final class SceneProjectDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.sceneProject] }

    @Published var project: StoryProject

    init() {
        project = StoryProject.starter()
    }

    init(configuration: ReadConfiguration) throws {
        project = try ProjectPersistence.shared.loadProject(from: configuration.file)
    }

    func snapshot(contentType: UTType) throws -> StoryProject {
        project
    }

    func fileWrapper(snapshot: StoryProject, configuration: WriteConfiguration) throws -> FileWrapper {
        try ProjectPersistence.shared.makeFileWrapper(for: snapshot)
    }
}

extension SceneProjectDocument: @unchecked Sendable {}
