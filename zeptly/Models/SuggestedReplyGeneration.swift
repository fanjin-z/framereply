import Foundation

nonisolated struct SuggestedReplyPromptMessage: Codable, Equatable, Sendable {
    let sender: String
    let senderName: String?
    let text: String
    let timeLabel: String
}

nonisolated enum SuggestedReplySummaryMode: String, Codable, Equatable, Sendable {
    case unchanged
    case incremental
    case rebuild
}

nonisolated struct SuggestedReplyGenerationRequest: Equatable, Sendable {
    let chatName: String
    let relationshipSubtitle: String
    let contactMemories: [ContactMemory]
    let currentInteractionGoal: String
    let preferredPersona: String
    let existingHistorySummary: String
    let summaryMode: SuggestedReplySummaryMode
    let olderMessagesToSummarize: [SuggestedReplyPromptMessage]
    let recentMessages: [SuggestedReplyPromptMessage]
    let traceID: ImportTraceID
}

nonisolated struct SuggestedReplyGenerationResult: Codable, Equatable, Sendable {
    let historySummary: String
    let replies: [String]
}

protocol SuggestedReplyGenerating {
    func generateSuggestedReplies(
        _ request: SuggestedReplyGenerationRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> SuggestedReplyGenerationResult
}

nonisolated enum SuggestedReplyResultDecoder {
    static func decode(
        content: String?,
        finishReason: String?,
        historySummaryFallback: String? = nil
    ) throws -> SuggestedReplyGenerationResult {
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

        let object: [String: Any]
        do {
            object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw StructuredOutputFailure(kind: .invalidJSON, codingPath: nil)
        }

        guard !object.isEmpty else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "root")
        }

        let summary = ["historySummary", "history_summary", "summary"]
            .compactMap { object[$0] as? String }
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? historySummaryFallback
        guard let summary, summary.count <= 6_000 else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "historySummary")
        }

        let repliesValue = object["replies"]
            ?? object["suggestedReplies"]
            ?? object["suggested_replies"]
        var replies = replyTexts(from: repliesValue)
        if replies.isEmpty,
            let first = object["reply1"] as? String,
            let second = object["reply2"] as? String
        {
            replies = [first, second]
        }
        replies = replies.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard replies.count == 2,
            replies.allSatisfy({ !$0.isEmpty && $0.count <= 800 }),
            Set(replies.map { $0.lowercased() }).count == 2
        else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "replies")
        }

        return SuggestedReplyGenerationResult(historySummary: summary, replies: replies)
    }

    static func repairHint(for failure: StructuredOutputFailure) -> String {
        "Previous output failed validation (\(failure.kind.rawValue) at \(failure.codingPath ?? "root")). Return only this exact JSON shape: \(SuggestedReplyPrompt.canonicalJSONExample)"
    }

    private static func clean(_ content: String?) -> String {
        var value = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.hasPrefix("```"), let firstNewline = value.firstIndex(of: "\n") {
            value = String(value[value.index(after: firstNewline)...])
            if let fence = value.range(of: "```", options: .backwards) {
                value = String(value[..<fence.lowerBound])
            }
        }
        if let firstBrace = value.firstIndex(of: "{"),
            let lastBrace = value.lastIndex(of: "}"),
            firstBrace <= lastBrace
        {
            value = String(value[firstBrace...lastBrace])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replyTexts(from value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings
        }
        guard let objects = value as? [[String: Any]] else {
            return []
        }
        return objects.compactMap { object in
            ["text", "reply", "content"].compactMap { object[$0] as? String }.first
        }
    }
}
