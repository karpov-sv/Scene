import Foundation

struct PromptRenderer {
    struct ChatTurn: Sendable {
        var roleLabel: String
        var content: String
    }

    struct Context: Sendable {
        var variables: [String: String] = [:]
        var sceneFullText: String = ""
        var conversationTurns: [ChatTurn] = []
        var contextSections: [String: String] = [:]
    }

    struct Result: Sendable {
        var renderedText: String
        var warnings: [String]
    }

    private struct ResolvedContext {
        var variables: [String: String]
        var conversationTurns: [ChatTurn]
    }

    private static let tokenRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
    }()

    func render(template: String, fallbackTemplate: String? = nil, context: Context) -> Result {
        let normalizedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (fallbackTemplate ?? "")
            : template

        let resolvedContext = makeResolvedContext(from: context)
        var warnings: [String] = []
        var rendered = replaceCanonicalTokens(in: normalizedTemplate, context: resolvedContext, warnings: &warnings)
        rendered = replaceLegacyVariables(in: rendered, context: resolvedContext)

        return Result(
            renderedText: rendered,
            warnings: uniqueWarnings(from: warnings)
        )
    }

    private func makeResolvedContext(from context: Context) -> ResolvedContext {
        var normalizedVariables: [String: String] = [:]

        for (key, value) in context.variables {
            normalizedVariables[key.lowercased()] = value
        }

        for (key, value) in context.contextSections {
            normalizedVariables[key.lowercased()] = value
        }

        if normalizedVariables["scene_full"] == nil {
            normalizedVariables["scene_full"] = context.sceneFullText
        }
        if normalizedVariables["context"] == nil {
            normalizedVariables["context"] = context.contextSections["context"] ?? ""
        }
        if normalizedVariables["context_compendium"] == nil {
            normalizedVariables["context_compendium"] = context.contextSections["context_compendium"] ?? ""
        }
        if normalizedVariables["context_scene_summaries"] == nil {
            normalizedVariables["context_scene_summaries"] = context.contextSections["context_scene_summaries"] ?? ""
        }
        if normalizedVariables["context_chapter_summaries"] == nil {
            normalizedVariables["context_chapter_summaries"] = context.contextSections["context_chapter_summaries"] ?? ""
        }
        if normalizedVariables["conversation"] == nil {
            normalizedVariables["conversation"] = Self.formattedConversation(from: context.conversationTurns)
        }

        return ResolvedContext(
            variables: normalizedVariables,
            conversationTurns: context.conversationTurns
        )
    }

    private func replaceCanonicalTokens(
        in text: String,
        context: ResolvedContext,
        warnings: inout [String]
    ) -> String {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = Self.tokenRegex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: output),
                  let expressionRange = Range(match.range(at: 1), in: output) else {
                continue
            }

            let expression = String(output[expressionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = evaluateExpression(
                expression,
                context: context,
                warnings: &warnings
            )
            output.replaceSubrange(fullRange, with: replacement)
        }
        return output
    }

    private func replaceLegacyVariables(in text: String, context: ResolvedContext) -> String {
        var output = text
        let legacyKeys = context.variables.keys.sorted {
            if $0.count == $1.count {
                return $0 < $1
            }
            return $0.count > $1.count
        }

        for key in legacyKeys {
            let token = "{\(key)}"
            output = output.replacingOccurrences(of: token, with: context.variables[key] ?? "")
        }
        return output
    }

    private func evaluateExpression(
        _ expression: String,
        context: ResolvedContext,
        warnings: inout [String]
    ) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            warnings.append("Empty template token `{{}}`.")
            return ""
        }

        if let functionCall = parseFunctionCall(trimmed) {
            return evaluateFunction(
                functionCall.name,
                arguments: functionCall.arguments,
                context: context,
                warnings: &warnings
            )
        }

        let key = trimmed.lowercased()
        guard let value = context.variables[key] else {
            warnings.append("Unknown template variable `{{\(trimmed)}}`.")
            return ""
        }

        return value
    }

    private func evaluateFunction(
        _ rawName: String,
        arguments: [String: String],
        context: ResolvedContext,
        warnings: inout [String]
    ) -> String {
        let name = rawName.lowercased()

        switch name {
        case "scene_tail":
            let chars = intArgument(
                named: "chars",
                in: arguments,
                defaultValue: 4500,
                minimum: 0,
                functionName: name,
                warnings: &warnings
            )
            let source = context.variables["scene_full"] ?? context.variables["scene"] ?? ""
            return suffix(source, maxChars: chars)

        case "chat_history":
            let turns = intArgument(
                named: "turns",
                in: arguments,
                defaultValue: 8,
                minimum: 0,
                functionName: name,
                warnings: &warnings
            )

            if turns == 0 {
                return ""
            }

            if !context.conversationTurns.isEmpty {
                let slice = context.conversationTurns.suffix(turns)
                return Self.formattedConversation(from: Array(slice))
            }

            return context.variables["conversation"] ?? ""

        case "context":
            let maxChars = optionalIntArgument(
                named: "max_chars",
                in: arguments,
                minimum: 0,
                functionName: name,
                warnings: &warnings
            )
            return truncate(context.variables["context"] ?? "", maxChars: maxChars)

        case "context_compendium", "context_entries":
            let maxChars = optionalIntArgument(
                named: "max_chars",
                in: arguments,
                minimum: 0,
                functionName: name,
                warnings: &warnings
            )
            return truncate(context.variables["context_compendium"] ?? "", maxChars: maxChars)

        case "context_scene_summaries":
            let maxChars = optionalIntArgument(
                named: "max_chars",
                in: arguments,
                minimum: 0,
                functionName: name,
                warnings: &warnings
            )
            return truncate(context.variables["context_scene_summaries"] ?? "", maxChars: maxChars)

        case "context_chapter_summaries":
            let maxChars = optionalIntArgument(
                named: "max_chars",
                in: arguments,
                minimum: 0,
                functionName: name,
                warnings: &warnings
            )
            return truncate(context.variables["context_chapter_summaries"] ?? "", maxChars: maxChars)

        default:
            warnings.append("Unknown template function `{{\(rawName)(...)}}`.")
            return ""
        }
    }

    private func parseFunctionCall(_ expression: String) -> (name: String, arguments: [String: String])? {
        guard let openIndex = expression.firstIndex(of: "("),
              expression.last == ")" else {
            return nil
        }

        let name = String(expression[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let argumentsStart = expression.index(after: openIndex)
        let argumentsEnd = expression.index(before: expression.endIndex)
        let argumentsBody = expression[argumentsStart..<argumentsEnd]

        return (name, parseArguments(String(argumentsBody)))
    }

    private func parseArguments(_ value: String) -> [String: String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }

        var parsed: [String: String] = [:]
        let pairs = trimmed.split(separator: ",", omittingEmptySubsequences: false)

        for rawPair in pairs {
            let pair = String(rawPair).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pair.isEmpty else { continue }

            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else {
                continue
            }

            let key = String(pieces[0]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }

            var argumentValue = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if argumentValue.hasPrefix("\""), argumentValue.hasSuffix("\""), argumentValue.count >= 2 {
                argumentValue = String(argumentValue.dropFirst().dropLast())
            } else if argumentValue.hasPrefix("'"), argumentValue.hasSuffix("'"), argumentValue.count >= 2 {
                argumentValue = String(argumentValue.dropFirst().dropLast())
            }

            parsed[key] = argumentValue
        }

        return parsed
    }

    private func intArgument(
        named name: String,
        in arguments: [String: String],
        defaultValue: Int,
        minimum: Int,
        functionName: String,
        warnings: inout [String]
    ) -> Int {
        guard let raw = arguments[name] else {
            return defaultValue
        }

        guard let parsed = Int(raw) else {
            warnings.append("Invalid `\(name)` value `\(raw)` for `{{\(functionName)(...)}}`; using \(defaultValue).")
            return defaultValue
        }

        if parsed < minimum {
            warnings.append("`\(name)` for `{{\(functionName)(...)}}` must be >= \(minimum); using \(minimum).")
            return minimum
        }

        return parsed
    }

    private func optionalIntArgument(
        named name: String,
        in arguments: [String: String],
        minimum: Int,
        functionName: String,
        warnings: inout [String]
    ) -> Int? {
        guard let raw = arguments[name] else {
            return nil
        }

        guard let parsed = Int(raw) else {
            warnings.append("Invalid `\(name)` value `\(raw)` for `{{\(functionName)(...)}}`; ignoring.")
            return nil
        }

        if parsed < minimum {
            warnings.append("`\(name)` for `{{\(functionName)(...)}}` must be >= \(minimum); using \(minimum).")
            return minimum
        }

        return parsed
    }

    private func truncate(_ text: String, maxChars: Int?) -> String {
        guard let maxChars else { return text }
        guard maxChars > 0 else { return "" }
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars))
    }

    private func suffix(_ text: String, maxChars: Int) -> String {
        guard maxChars > 0 else { return "" }
        guard text.count > maxChars else { return text }
        return String(text.suffix(maxChars))
    }

    private func uniqueWarnings(from warnings: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []

        for warning in warnings {
            if seen.insert(warning).inserted {
                unique.append(warning)
            }
        }
        return unique
    }

    private static func formattedConversation(from turns: [ChatTurn]) -> String {
        turns
            .map { turn in
                "\(turn.roleLabel): \(turn.content)"
            }
            .joined(separator: "\n\n")
    }
}
