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

    static func choosePromptExportURL(defaultProjectName: String) -> URL? {
        chooseJSONExportURL(
            title: "Export Prompt Templates",
            message: "Export prompt templates as JSON (includes modified built-in templates).",
            prompt: "Export",
            suggestedName: "\(defaultProjectName)-prompts.json"
        )
    }

    static func choosePromptImportURL() -> URL? {
        chooseJSONImportURL(
            title: "Import Prompt Templates",
            message: "Select a prompt template export JSON file.",
            prompt: "Import"
        )
    }

    static func chooseCompendiumExportURL(defaultProjectName: String) -> URL? {
        chooseJSONExportURL(
            title: "Export Compendium",
            message: "Export compendium entries as JSON.",
            prompt: "Export",
            suggestedName: "\(defaultProjectName)-compendium.json"
        )
    }

    static func chooseCompendiumImportURL() -> URL? {
        chooseJSONImportURL(
            title: "Import Compendium",
            message: "Select a compendium export JSON file.",
            prompt: "Import"
        )
    }

    static func chooseProjectExchangeExportURL(defaultProjectName: String) -> URL? {
        chooseJSONExportURL(
            title: "Export Project as JSON",
            message: "Export the full project as a single JSON file.",
            prompt: "Export",
            suggestedName: "\(defaultProjectName)-project.json"
        )
    }

    static func chooseProjectTextExportURL(defaultProjectName: String) -> URL? {
        chooseTypedExportURL(
            title: "Export Project as Plain Text",
            message: "Export chapter and scene text into a single plain text file.",
            prompt: "Export",
            suggestedName: "\(defaultProjectName).txt",
            contentType: .plainText
        )
    }

    static func chooseProjectHTMLExportURL(defaultProjectName: String) -> URL? {
        chooseTypedExportURL(
            title: "Export Project as HTML",
            message: "Export chapter and scene text into a single HTML file.",
            prompt: "Export",
            suggestedName: "\(defaultProjectName).html",
            contentType: .html
        )
    }

    static func chooseProjectEPUBExportURL(defaultProjectName: String) -> URL? {
        chooseTypedExportURL(
            title: "Export Project as EPUB",
            message: "Export chapter and scene text as an EPUB ebook. This also embeds full Scene project data for Scene-to-Scene import.",
            prompt: "Export",
            suggestedName: "\(defaultProjectName).epub",
            contentType: UTType(filenameExtension: "epub") ?? .data
        )
    }

    static func chooseProjectExchangeImportURL() -> URL? {
        chooseJSONImportURL(
            title: "Import Project from JSON",
            message: "Select a full-project JSON export to import.",
            prompt: "Import"
        )
    }

    static func chooseProjectEPUBImportURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Project from EPUB"
        panel.message = "Select an EPUB file to import."
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.urls.first
    }

    static func confirmProjectImportReplacement() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace Current Project Content?"
        alert.informativeText = "Importing a project JSON will replace chapters, scenes, compendium, prompts, and workshop chats in the current project."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func confirmProjectEPUBImportReplacement() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Import EPUB Into Current Project?"
        alert.informativeText = "If the EPUB contains embedded Scene project data, it will replace the full project. Otherwise, chapter/scene text and project title will be replaced from EPUB content."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func chooseJSONExportURL(
        title: String,
        message: String,
        prompt: String,
        suggestedName: String
    ) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = sanitizeFileName(suggestedName)
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return nil
        }

        return selectedURL
    }

    private static func chooseJSONImportURL(
        title: String,
        message: String,
        prompt: String
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.urls.first
    }

    private static func chooseTypedExportURL(
        title: String,
        message: String,
        prompt: String,
        suggestedName: String,
        contentType: UTType
    ) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = sanitizeFileName(suggestedName)
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
