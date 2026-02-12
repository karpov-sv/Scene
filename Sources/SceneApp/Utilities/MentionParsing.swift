import Foundation

enum MentionTrigger: Character {
    case tag = "@"
    case scene = "#"
}

struct MentionAutocompleteQuery: Equatable {
    let trigger: MentionTrigger
    let query: String
    let tokenRange: NSRange
}

struct MentionSuggestion: Identifiable, Equatable {
    let id: String
    let trigger: MentionTrigger
    let label: String
    let subtitle: String?
    let insertion: String
}

struct MentionTokenCollection {
    var tags: Set<String> = []
    var scenes: Set<String> = []

    var isEmpty: Bool {
        tags.isEmpty && scenes.isEmpty
    }
}

enum MentionParsing {
    static func normalize(_ raw: String) -> String {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
        return collapsed.lowercased()
    }

    static func activeQuery(in text: String, caretLocation: Int) -> MentionAutocompleteQuery? {
        let nsText = text as NSString
        guard caretLocation > 0, caretLocation <= nsText.length else {
            return nil
        }

        var tokenStart = caretLocation
        while tokenStart > 0 {
            guard let scalar = UnicodeScalar(nsText.character(at: tokenStart - 1)) else {
                break
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                break
            }
            tokenStart -= 1
        }

        let range = NSRange(location: tokenStart, length: caretLocation - tokenStart)
        guard range.length >= 1 else { return nil }
        let token = nsText.substring(with: range)

        guard let first = token.first,
              let trigger = MentionTrigger(rawValue: first) else {
            return nil
        }

        var query = String(token.dropFirst())
        if query.hasPrefix("[") {
            query.removeFirst()
        }
        if query.contains("]") {
            return nil
        }

        query = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return MentionAutocompleteQuery(
            trigger: trigger,
            query: query,
            tokenRange: range
        )
    }

    static func replacingToken(in text: String, range: NSRange, with replacement: String) -> String? {
        let nsText = text as NSString
        guard NSMaxRange(range) <= nsText.length else { return nil }
        return nsText.replacingCharacters(in: range, with: replacement)
    }

    static func extractMentionTokens(from text: String) -> MentionTokenCollection {
        var tokens = MentionTokenCollection()

        capturedValues(in: text, pattern: "@\\[([^\\]]+)\\]").forEach { raw in
            let key = normalize(raw)
            if !key.isEmpty {
                tokens.tags.insert(key)
            }
        }

        capturedValues(in: text, pattern: "#\\[([^\\]]+)\\]").forEach { raw in
            let key = normalize(raw)
            if !key.isEmpty {
                tokens.scenes.insert(key)
            }
        }

        capturedValues(in: text, pattern: "(?<!\\S)@([\\p{L}\\p{N}_\\-]+)").forEach { raw in
            let key = normalize(raw)
            if !key.isEmpty {
                tokens.tags.insert(key)
            }
        }

        capturedValues(in: text, pattern: "(?<!\\S)#([\\p{L}\\p{N}_\\-]+)").forEach { raw in
            let key = normalize(raw)
            if !key.isEmpty {
                tokens.scenes.insert(key)
            }
        }

        return tokens
    }

    private static func capturedValues(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let capture = match.range(at: 1)
            guard capture.location != NSNotFound else { return nil }
            return nsText.substring(with: capture)
        }
    }
}
