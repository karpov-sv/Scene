import AppKit
import UniformTypeIdentifiers

@MainActor
enum ProjectDialogs {
    static func chooseNewProjectURL(suggestedName: String = "Untitled") -> URL? {
        let panel = NSSavePanel()
        panel.title = "Create New Project"
        panel.message = "Choose where to create the new project."
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sanitizeFileName(suggestedName)
        if let projectType = UTType(filenameExtension: ProjectPersistence.projectDirectoryExtension) {
            panel.allowedContentTypes = [projectType]
        }
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return nil
        }

        return selectedURL
    }

    static func chooseExistingProjectURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.message = "Select an existing Scene project folder."
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.urls.first
    }

    static func chooseDuplicateDestinationURL(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Duplicate Project"
        panel.message = "Choose where to save the duplicate project."
        panel.prompt = "Duplicate"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sanitizeFileName(defaultName)
        if let projectType = UTType(filenameExtension: ProjectPersistence.projectDirectoryExtension) {
            panel.allowedContentTypes = [projectType]
        }
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return nil
        }

        return selectedURL
    }

    private static func sanitizeFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed
        let disallowed = CharacterSet(charactersIn: "/:\\")
        let sanitized = base.components(separatedBy: disallowed).joined(separator: "-")
        return sanitized
    }
}
