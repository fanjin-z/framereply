//
//  ChatImportAnalysisDecoder.swift
//  zeptly
//

import Foundation

nonisolated enum ChatImportAnalysisDecoder {
    static func decode(
        content: String?,
        finishReason: String?,
        candidateIDs: Set<String>
    ) throws -> ChatImportAnalysis {
        if finishReason == "length" {
            throw StructuredOutputFailure(kind: .truncatedResponse, codingPath: nil)
        }

        let cleaned = clean(content)
        guard !cleaned.isEmpty else {
            throw StructuredOutputFailure(kind: .emptyResponse, codingPath: nil)
        }
        guard let data = cleaned.data(using: .utf8) else {
            throw StructuredOutputFailure(kind: .invalidJSON, codingPath: nil)
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw StructuredOutputFailure(kind: .invalidJSON, codingPath: nil)
        }

        let analysis: ChatImportAnalysis
        do {
            analysis = try JSONDecoder().decode(ChatImportAnalysis.self, from: data)
        } catch let error as DecodingError {
            throw StructuredOutputFailure(
                kind: .schemaMismatch,
                codingPath: codingPath(for: error)
            )
        } catch {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: nil)
        }

        return try validate(analysis, candidateIDs: candidateIDs)
    }

    static func validate(
        _ analysis: ChatImportAnalysis,
        candidateIDs: Set<String>
    ) throws -> ChatImportAnalysis {
        guard !analysis.messages.isEmpty,
            analysis.messages.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw StructuredOutputFailure(kind: .incompleteMessages, codingPath: "messages")
        }
        guard (0...1).contains(analysis.matchConfidence) else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "matchConfidence")
        }
        if let matchedChatID = analysis.matchedChatID, !candidateIDs.contains(matchedChatID) {
            throw StructuredOutputFailure(kind: .invalidCandidateID, codingPath: "matchedChatID")
        }

        return analysis
    }

    static func repairHint(for failure: StructuredOutputFailure) -> String {
        let location = failure.codingPath.map { " at coding path \($0)" } ?? ""
        return "The previous output failed \(failure.kind.rawValue) validation\(location). Return the complete JSON contract below."
    }

    private static func clean(_ content: String?) -> String {
        guard var text = content?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return ""
        }
        while text.first == "\u{FEFF}" {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard text.hasPrefix("```"), text.hasSuffix("```") else {
            return text
        }
        guard let firstNewline = text.firstIndex(of: "\n") else {
            return text
        }
        let bodyStart = text.index(after: firstNewline)
        let closingFence = text.index(text.endIndex, offsetBy: -3)
        guard bodyStart <= closingFence else {
            return text
        }
        return String(text[bodyStart..<closingFence])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func codingPath(for error: DecodingError) -> String? {
        let path: [any CodingKey]
        let appendedKey: (any CodingKey)?
        switch error {
        case let .keyNotFound(key, context):
            path = context.codingPath
            appendedKey = key
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            path = context.codingPath
            appendedKey = nil
        @unknown default:
            return nil
        }

        let keys = path + (appendedKey.map { [$0] } ?? [])
        guard !keys.isEmpty else { return nil }
        return keys.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                if !result.isEmpty { result += "." }
                result += key.stringValue
            }
        }
    }
}
