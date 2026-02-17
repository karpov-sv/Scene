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
    static var autosavesInPlace: Bool { false }

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
        let wrapper = try ProjectPersistence.shared.makeFileWrapper(for: snapshot)

        // Preserve checkpoint snapshots stored alongside the project package
        // when the document rewrites the file wrapper.
        if wrapper.fileWrappers?[ProjectPersistence.checkpointsDirectoryName] == nil,
           let existingCheckpoints = configuration.existingFile?.fileWrappers?[ProjectPersistence.checkpointsDirectoryName] {
            let checkpointsCopy = duplicateFileWrapper(existingCheckpoints)
            checkpointsCopy.preferredFilename = ProjectPersistence.checkpointsDirectoryName
            wrapper.addFileWrapper(checkpointsCopy)
        }

        return wrapper
    }

    private func duplicateFileWrapper(_ source: FileWrapper) -> FileWrapper {
        if source.isDirectory {
            let duplicatedChildren = (source.fileWrappers ?? [:]).mapValues { duplicateFileWrapper($0) }
            let copy = FileWrapper(directoryWithFileWrappers: duplicatedChildren)
            copy.preferredFilename = source.preferredFilename
            return copy
        }

        if source.isRegularFile {
            let copy = FileWrapper(regularFileWithContents: source.regularFileContents ?? Data())
            copy.preferredFilename = source.preferredFilename
            return copy
        }

        if source.isSymbolicLink, let destinationURL = source.symbolicLinkDestinationURL {
            let copy = FileWrapper(symbolicLinkWithDestinationURL: destinationURL)
            copy.preferredFilename = source.preferredFilename
            return copy
        }

        let copy = FileWrapper(regularFileWithContents: Data())
        copy.preferredFilename = source.preferredFilename
        return copy
    }
}

extension SceneProjectDocument: @unchecked Sendable {}
