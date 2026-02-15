import Foundation

struct AIRequestPreview {
    struct Header {
        let name: String
        let value: String
    }

    let url: String
    let method: String
    let headers: [Header]
    let bodyJSON: String
    let bodyHumanReadable: String
}

class AIProviderServiceBase: AIService, @unchecked Sendable {
    func generateText(_ request: TextGenerationRequest, settings: GenerationSettings) async throws -> String {
        try await generateText(request, settings: settings, onPartial: nil)
    }

    func generateText(
        _ request: TextGenerationRequest,
        settings: GenerationSettings,
        onPartial: (@MainActor (String) -> Void)?
    ) async throws -> String {
        let result = try await generateTextResult(
            request,
            settings: settings,
            onPartial: onPartial
        )
        return result.text
    }

    func generateTextResult(
        _ request: TextGenerationRequest,
        settings: GenerationSettings,
        onPartial: (@MainActor (String) -> Void)?
    ) async throws -> TextGenerationResult {
        fatalError("Subclasses must override generateTextResult(_:settings:onPartial:).")
    }

    func validateModel(in request: TextGenerationRequest) throws {
        guard !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.missingModel
        }
    }

    func normalizedTimeout(from timeout: Double) -> TimeInterval {
        TimeInterval(min(max(timeout, 1), 3600))
    }

    func prettyPrintedJSONData<T: Encodable>(_ value: T) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: encoded)
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    func previewBodyStrings<T: Encodable>(for payload: T) throws -> (rawJSON: String, humanReadable: String) {
        let bodyData = try prettyPrintedJSONData(payload)
        let rawJSON = String(data: bodyData, encoding: .utf8) ?? "{}"
        let humanReadable = makeHumanReadablePreviewBody(from: bodyData) ?? rawJSON
        return (rawJSON, humanReadable)
    }

    func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    func fallbackProviderErrorMessage(from data: Data, statusCode: Int) -> String {
        if let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return "HTTP \(statusCode): \(String(raw.prefix(280)))"
        }

        return "HTTP \(statusCode)"
    }

    func sortedModelIDs<S: Sequence>(_ rawModelIDs: S) -> [String] where S.Element == String {
        let modelIDs = Set(
            rawModelIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        return modelIDs.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func makeBaseV1URL(from endpoint: String, removingSuffixes suffixes: [String]) throws -> URL {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIServiceError.invalidEndpoint
        }

        guard var components = URLComponents(string: trimmed),
              let rawPath = components.path.removingPercentEncoding else {
            throw AIServiceError.invalidEndpoint
        }

        let pathWithoutTrailingSlash = rawPath.hasSuffix("/")
            ? String(rawPath.dropLast())
            : rawPath

        let sortedSuffixes = suffixes.sorted { $0.count > $1.count }
        let normalizedPath: String
        if let matchedSuffix = sortedSuffixes.first(where: { pathWithoutTrailingSlash.hasSuffix($0) }) {
            normalizedPath = String(pathWithoutTrailingSlash.dropLast(matchedSuffix.count))
        } else {
            normalizedPath = pathWithoutTrailingSlash
        }

        let trimmedPath = normalizedPath.hasSuffix("/")
            ? String(normalizedPath.dropLast())
            : normalizedPath

        if trimmedPath.hasSuffix("/v1") {
            components.path = trimmedPath
        } else if trimmedPath.isEmpty {
            components.path = "/v1"
        } else {
            components.path = trimmedPath + "/v1"
        }

        guard let normalizedURL = components.url else {
            throw AIServiceError.invalidEndpoint
        }
        return normalizedURL
    }

    private func makeHumanReadablePreviewBody(from bodyData: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: bodyData, options: [.fragmentsAllowed]) else {
            return nil
        }
        return renderHumanReadableValue(object, indentLevel: 0)
    }

    private func renderHumanReadableValue(_ value: Any, indentLevel: Int) -> String {
        let baseIndent = String(repeating: "  ", count: indentLevel)
        
        switch value {
        case let dictionary as [String: Any]:
            if dictionary.isEmpty { return "{}" }

            var lines = ["{"]
            for key in dictionary.keys.sorted() {
                guard let item = dictionary[key] else { continue }
                let rendered = renderHumanReadableValue(item, indentLevel: 1)
                let itemIndent = String(repeating: "  ", count: 1)
                lines.append(contentsOf: labeledBlock(
                    label: "\(itemIndent)\(key)",
                    renderedValue: rendered,
                    nestedIndentLevel: 1
                ))
            }
            lines.append("}")
            return lines.joined(separator: "\n")

        case let array as [Any]:
            if array.isEmpty { return "[]" }

            var lines = ["\(baseIndent)["]
            let nestedIndent = String(repeating: "  ", count: indentLevel + 1)

            for item in array {
                let rendered = renderHumanReadableValue(item, indentLevel: indentLevel + 1)
                if rendered.contains("\n") {
                    lines.append(contentsOf: rendered
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "\(nestedIndent)\($0)" })
                } else {
                    lines.append("\(rendered)")
                }
            }
            
            lines.append("\(baseIndent)]")
            return lines.joined(separator: "\n")

        case let string as String:
            return renderHumanReadableString(string)

        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue

        case _ as NSNull:
            return "null"

        default:
            return String(describing: value)
        }
    }

    private func labeledBlock(
        label: String,
        renderedValue: String,
        nestedIndentLevel: Int
    ) -> [String] {
        if renderedValue.contains("\n") {
            let nestedIndent = String(repeating: "  ", count: nestedIndentLevel)
            var lines = ["\(label):"]
            lines.append(contentsOf: renderedValue
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "\(nestedIndent)\($0)" })
            return lines
        }
        return ["\(label): \(renderedValue)"]
    }

    private func renderHumanReadableString(_ raw: String) -> String {
        if raw.isEmpty {
            return "\"\""
        }

        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let hasSpecial = normalized.contains("\n")
            || normalized.contains("\r")
            || normalized.contains("\t")
            || normalized.contains("\\")
            || normalized.contains("\"")

        guard hasSpecial else {
            return "\"\(normalized)\""
        }

        let visibleTabs = normalized.replacingOccurrences(of: "\t", with: "⇥\t")
        let lines = visibleTabs
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\r", with: "␍") }

        var block = ["\""]
        block.append(contentsOf: lines)
        block.append("\"")
        return block.joined(separator: "\n")
    }
}
