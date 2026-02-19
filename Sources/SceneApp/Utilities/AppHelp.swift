import AppKit
import Foundation

@MainActor
enum AppHelp {
    enum Topic {
        case home
        case workspace
        case editor
        case textGeneration
        case rewriting
        case compendium
        case context
        case mentions
        case rollingMemory
        case workshop
        case checkpoints
        case aiProviders
        case promptTemplates
        case importExport
        case keyboardShortcuts

        var anchor: String {
            switch self {
            case .home: return "home"
            case .workspace: return "workspace"
            case .editor: return "editor"
            case .textGeneration: return "text-generation"
            case .rewriting: return "rewriting"
            case .compendium: return "compendium"
            case .context: return "context"
            case .mentions: return "mentions"
            case .rollingMemory: return "rolling-memory"
            case .workshop: return "workshop"
            case .checkpoints: return "checkpoints"
            case .aiProviders: return "ai-providers"
            case .promptTemplates: return "prompt-templates"
            case .importExport: return "import-export"
            case .keyboardShortcuts: return "keyboard-shortcuts"
            }
        }

        /// HTML filename (without extension) for the topic page.
        var page: String {
            switch self {
            case .home: return "index"
            default: return anchor
            }
        }
    }

    private static let defaultHelpBookName = "Scene Help"
    private static let helpBookFolderName = "SceneHelp"
    private static let helpBookFolderExtension = "help"
    private static let helpBookSubdirectory = "SceneHelp.help/Contents/Resources/en.lproj"
    private static let homePageName = "index"

    @discardableResult
    static func open(_ topic: Topic = .home) -> Bool {
        if openSystemHelpAnchor(topic.anchor) {
            return true
        }

        if openBundledHelpPage(topic: topic) {
            return true
        }

        return openReadmeFallback()
    }

    @discardableResult
    private static func openSystemHelpAnchor(_ anchor: String) -> Bool {
        guard Bundle.main.url(
            forResource: helpBookFolderName,
            withExtension: helpBookFolderExtension
        ) != nil else {
            return false
        }

        NSHelpManager.shared.registerBooks(in: Bundle.main)

        let infoName = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String
        let helpBookName = infoName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBook = (helpBookName?.isEmpty == false) ? helpBookName! : defaultHelpBookName
        NSHelpManager.shared.openHelpAnchor(anchor, inBook: resolvedBook)
        return true
    }

    @discardableResult
    private static func openBundledHelpPage(topic: Topic) -> Bool {
        guard let pageURL = helpPageURL(page: topic.page) else {
            return false
        }

        var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
        components?.fragment = topic.anchor
        guard let targetURL = components?.url else {
            return false
        }
        return NSWorkspace.shared.open(targetURL)
    }

    private static func helpPageURL(page: String) -> URL? {
        let htmlRelPath = "\(helpBookFolderName).\(helpBookFolderExtension)/Contents/Resources/en.lproj/\(page).html"

        if let resourceRoot = Bundle.main.resourceURL {
            let directURL = resourceRoot.appendingPathComponent(htmlRelPath, isDirectory: false)
            if FileManager.default.fileExists(atPath: directURL.path) {
                return directURL
            }
        }

        // Probe relative to CWD so `swift run` from the project root finds the file
        // under Resources/SceneHelp.help/…
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for prefix in ["Resources", "."] {
            let candidate = cwdURL.appendingPathComponent(prefix, isDirectory: true)
                                  .appendingPathComponent(htmlRelPath, isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return Bundle.main.url(
            forResource: page,
            withExtension: "html",
            subdirectory: helpBookSubdirectory
        )
    }

    @discardableResult
    private static func openReadmeFallback() -> Bool {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        let cwdURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(cwdURL.appendingPathComponent("README.md", isDirectory: false))

        let bundleDir = Bundle.main.bundleURL.deletingLastPathComponent()
        candidates.append(bundleDir.appendingPathComponent("README.md", isDirectory: false))
        candidates.append(
            bundleDir
                .deletingLastPathComponent()
                .appendingPathComponent("README.md", isDirectory: false)
        )

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return NSWorkspace.shared.open(candidate)
        }
        return false
    }
}
