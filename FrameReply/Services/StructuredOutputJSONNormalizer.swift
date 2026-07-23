import Foundation

nonisolated struct StructuredOutputDecodingResult<Value> {
    let value: Value
    let recovered: Bool
}

nonisolated enum StructuredOutputJSONNormalizer {
    struct Result {
        let object: [String: Any]
        let recovered: Bool
    }

    static func decodeObject(from content: String?) throws -> Result {
        let text = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw StructuredOutputFailure(kind: .emptyResponse, codingPath: nil)
        }

        if let object = parseObject(text) {
            return Result(object: object, recovered: false)
        }
        if isValidNonObjectJSON(text) {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "root")
        }
        if let fenced = fencedBody(in: text) {
            if let object = parseObject(fenced) {
                return Result(object: object, recovered: true)
            }
            if isValidNonObjectJSON(fenced) {
                throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "root")
            }
            throw StructuredOutputFailure(kind: .invalidJSON, codingPath: nil)
        }
        if text.hasPrefix("```") || text.hasSuffix("```") {
            throw StructuredOutputFailure(kind: .invalidJSON, codingPath: nil)
        }

        let candidates = balancedObjectCandidates(in: text)
        guard candidates.count == 1,
            !hasArrayWrapper(around: candidates[0], in: text),
            let object = parseObject(candidates[0])
        else {
            throw StructuredOutputFailure(kind: .invalidJSON, codingPath: nil)
        }
        return Result(object: object, recovered: true)
    }

    private static func parseObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: data),
            let object = value as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func isValidNonObjectJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(
                with: data, options: [.fragmentsAllowed])
        else {
            return false
        }
        return !(value is [String: Any])
    }

    private static func hasArrayWrapper(around candidate: String, in text: String) -> Bool {
        guard let range = text.range(of: candidate) else { return true }
        return text[..<range.lowerBound].contains("[")
            || text[range.upperBound...].contains("]")
    }

    private static func fencedBody(in text: String) -> String? {
        guard text.hasPrefix("```"), text.hasSuffix("```"),
            let firstLineEnd = text.firstIndex(of: "\n")
        else {
            return nil
        }
        let header = text[text.index(text.startIndex, offsetBy: 3)..<firstLineEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard header.isEmpty || header == "json" else { return nil }

        let closingStart = text.index(text.endIndex, offsetBy: -3)
        guard firstLineEnd < closingStart else { return nil }
        return String(text[text.index(after: firstLineEnd)..<closingStart])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func balancedObjectCandidates(in text: String) -> [String] {
        var candidates: [String] = []
        var start: String.Index?
        var depth = 0
        var inString = false
        var escaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let startIndex = start {
                    let end = text.index(after: index)
                    candidates.append(String(text[startIndex..<end]))
                    start = nil
                }
            }
            index = text.index(after: index)
        }
        return depth == 0 ? candidates : []
    }
}
