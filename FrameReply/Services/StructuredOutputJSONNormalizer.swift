import CoreFoundation
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

nonisolated enum StrictStructuredOutputValidator {
    static func validate(content: String?, schema: [String: Any]) throws {
        let text = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, let data = text.data(using: .utf8) else {
            throw StructuredOutputFailure(kind: .emptyResponse, codingPath: nil)
        }

        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw StructuredOutputFailure(kind: .invalidJSON, codingPath: nil)
        }
        try validate(value, against: schema, path: "root")
    }

    private static func validate(_ value: Any, against schema: [String: Any], path: String) throws {
        let allowedTypes: [String]
        if let type = schema["type"] as? String {
            allowedTypes = [type]
        } else {
            allowedTypes = schema["type"] as? [String] ?? []
        }
        let actualType = jsonType(of: value)
        let typeMatches =
            allowedTypes.contains(actualType)
            || (actualType == "integer" && allowedTypes.contains("number"))
        if !allowedTypes.isEmpty, !typeMatches {
            throw schemaMismatch(path)
        }

        if let allowedValues = schema["enum"] as? [Any],
            !allowedValues.contains(where: { jsonValuesEqual($0, value) })
        {
            throw schemaMismatch(path)
        }

        if let object = value as? [String: Any] {
            try validateObject(object, against: schema, path: path)
        } else if let array = value as? [Any] {
            try validateArray(array, against: schema, path: path)
        } else if let string = value as? String {
            if let minimum = schema["minLength"] as? Int, string.count < minimum {
                throw schemaMismatch(path)
            }
            if let maximum = schema["maxLength"] as? Int, string.count > maximum {
                throw schemaMismatch(path)
            }
        } else if let number = numericValue(value) {
            if let minimum = numericValue(schema["minimum"]), number < minimum {
                throw schemaMismatch(path)
            }
            if let maximum = numericValue(schema["maximum"]), number > maximum {
                throw schemaMismatch(path)
            }
        }
    }

    private static func validateObject(
        _ object: [String: Any],
        against schema: [String: Any],
        path: String
    ) throws {
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let required = Set(schema["required"] as? [String] ?? [])
        if let missing = required.subtracting(object.keys).sorted().first {
            throw schemaMismatch("\(path).\(missing)")
        }
        if schema["additionalProperties"] as? Bool == false,
            let extra = Set(object.keys).subtracting(properties.keys).sorted().first
        {
            throw schemaMismatch("\(path).\(extra)")
        }
        for key in object.keys.sorted() {
            guard let propertySchema = properties[key] as? [String: Any],
                let propertyValue = object[key]
            else { continue }
            try validate(propertyValue, against: propertySchema, path: "\(path).\(key)")
        }
    }

    private static func validateArray(
        _ array: [Any],
        against schema: [String: Any],
        path: String
    ) throws {
        if let minimum = schema["minItems"] as? Int, array.count < minimum {
            throw schemaMismatch(path)
        }
        if let maximum = schema["maxItems"] as? Int, array.count > maximum {
            throw schemaMismatch(path)
        }
        guard let itemSchema = schema["items"] as? [String: Any] else { return }
        for (index, item) in array.enumerated() {
            try validate(item, against: itemSchema, path: "\(path)[\(index)]")
        }
    }

    private static func jsonType(of value: Any) -> String {
        if value is NSNull { return "null" }
        if value is [String: Any] { return "object" }
        if value is [Any] { return "array" }
        if value is String { return "string" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return "boolean" }
            return number.doubleValue.rounded() == number.doubleValue ? "integer" : "number"
        }
        return "unknown"
    }

    private static func numericValue(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return number.doubleValue
    }

    private static func jsonValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if lhs is NSNull, rhs is NSNull { return true }
        return (lhs as? NSObject)?.isEqual(rhs) == true
    }

    private static func schemaMismatch(_ path: String) -> StructuredOutputFailure {
        StructuredOutputFailure(kind: .schemaMismatch, codingPath: path)
    }
}
