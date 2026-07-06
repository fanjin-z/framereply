import Foundation

nonisolated struct SuggestedReplyPromptMessage: Codable, Equatable, Sendable {
    let id: UUID
    let sender: String
    let senderName: String?
    let text: String
    let timeLabel: String
}

nonisolated enum ContactMemoryChangeAction: String, Codable, Equatable, Sendable {
    case add
    case update
    case archive
}

nonisolated struct ContactMemoryChange: Codable, Equatable, Sendable {
    let action: ContactMemoryChangeAction
    let targetMemoryID: UUID?
    let text: String?
    let kind: ContactMemoryKind?
    let sourceMessageIDs: [UUID]
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
    let persona: PersonaPromptContext
    let personaLearningMessages: [SuggestedReplyPromptMessage]
    let existingHistorySummary: String
    let summaryMode: SuggestedReplySummaryMode
    let olderMessagesToSummarize: [SuggestedReplyPromptMessage]
    let recentMessages: [SuggestedReplyPromptMessage]
    let draftingInput: String?
    let traceID: ImportTraceID

    init(
        chatName: String,
        relationshipSubtitle: String,
        contactMemories: [ContactMemory],
        currentInteractionGoal: String,
        persona: PersonaPromptContext,
        personaLearningMessages: [SuggestedReplyPromptMessage],
        existingHistorySummary: String,
        summaryMode: SuggestedReplySummaryMode,
        olderMessagesToSummarize: [SuggestedReplyPromptMessage],
        recentMessages: [SuggestedReplyPromptMessage],
        draftingInput: String? = nil,
        traceID: ImportTraceID
    ) {
        self.chatName = chatName
        self.relationshipSubtitle = relationshipSubtitle
        self.contactMemories = contactMemories
        self.currentInteractionGoal = currentInteractionGoal
        self.persona = persona
        self.personaLearningMessages = personaLearningMessages
        self.existingHistorySummary = existingHistorySummary
        self.summaryMode = summaryMode
        self.olderMessagesToSummarize = olderMessagesToSummarize
        self.recentMessages = recentMessages
        self.draftingInput = draftingInput
        self.traceID = traceID
    }
}

extension SuggestedReplyGenerationRequest {
    init(
        chatName: String,
        relationshipSubtitle: String,
        contactMemories: [ContactMemory],
        currentInteractionGoal: String,
        preferredPersona: String,
        existingHistorySummary: String,
        summaryMode: SuggestedReplySummaryMode,
        olderMessagesToSummarize: [SuggestedReplyPromptMessage],
        recentMessages: [SuggestedReplyPromptMessage],
        draftingInput: String? = nil,
        traceID: ImportTraceID
    ) {
        self.init(
            chatName: chatName,
            relationshipSubtitle: relationshipSubtitle,
            contactMemories: contactMemories,
            currentInteractionGoal: currentInteractionGoal,
            persona: PersonaPromptContext(
                id: PersonaDefaults.professionalID,
                name: preferredPersona,
                purposeInstructions: preferredPersona,
                resolvedStyle: [],
                descriptiveObservations: [],
                alwaysFollowRules: "",
                registryVersion: PersonaStyleDimensionRegistry.version,
                resolverVersion: PersonaStyleResolver.version
            ),
            personaLearningMessages: [],
            existingHistorySummary: existingHistorySummary,
            summaryMode: summaryMode,
            olderMessagesToSummarize: olderMessagesToSummarize,
            recentMessages: recentMessages,
            draftingInput: draftingInput,
            traceID: traceID
        )
    }
}

nonisolated struct PersonaTraitChange: Codable, Equatable, Sendable {
    let dimensionKey: String
    let levelBand: PersonaStyleBand?
    let observation: String
    let sourceMessageIDs: [UUID]
}

nonisolated struct SuggestedReplyGenerationResult: Codable, Equatable, Sendable {
    let historySummary: String
    let replies: [String]
    let memoryChanges: [ContactMemoryChange]
    let personaTraitChanges: [PersonaTraitChange]

    init(
        historySummary: String,
        replies: [String],
        memoryChanges: [ContactMemoryChange] = [],
        personaTraitChanges: [PersonaTraitChange] = []
    ) {
        self.historySummary = historySummary
        self.replies = replies
        self.memoryChanges = memoryChanges
        self.personaTraitChanges = personaTraitChanges
    }
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

        let summaryKeys = ["historySummary", "history_summary", "summary"]
        guard let summaryValue = summaryKeys.lazy.compactMap({ object[$0] }).first else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "historySummary")
        }
        let summary: String
        if summaryValue is NSNull {
            guard let historySummaryFallback else {
                throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "historySummary")
            }
            summary = historySummaryFallback
        } else if let value = summaryValue as? String {
            summary = value.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "historySummary")
        }
        guard summary.count <= 2_000 else {
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
            replies.allSatisfy({ !$0.isEmpty && $0.count <= 500 }),
            Set(replies.map { $0.lowercased() }).count == 2
        else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "replies")
        }

        guard let memoryChangeObjects = object["memoryChanges"] as? [[String: Any]],
            memoryChangeObjects.count <= 8
        else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "memoryChanges")
        }
        let memoryChanges = try memoryChangeObjects.enumerated().map { index, object in
            try decodeMemoryChange(object, index: index)
        }

        let traitObjects = object["personaTraitChanges"] as? [[String: Any]] ?? []
        guard traitObjects.count <= PersonaStyleDimensionRegistry.learnableDefinitions.count else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "personaTraitChanges")
        }
        let personaTraitChanges = try traitObjects.enumerated().map { index, value in
            try decodePersonaTraitChange(value, index: index)
        }
        guard Set(personaTraitChanges.map(\.dimensionKey)).count == personaTraitChanges.count else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "personaTraitChanges.dimensionKey")
        }

        return SuggestedReplyGenerationResult(
            historySummary: summary,
            replies: replies,
            memoryChanges: memoryChanges,
            personaTraitChanges: personaTraitChanges
        )
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

    private static func decodeMemoryChange(
        _ object: [String: Any],
        index: Int
    ) throws -> ContactMemoryChange {
        let path = "memoryChanges[\(index)]"
        guard let actionValue = object["action"] as? String,
            let action = ContactMemoryChangeAction(rawValue: actionValue),
            let sourceValues = object["sourceMessageIDs"] as? [String],
            (1...3).contains(sourceValues.count)
        else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: path)
        }

        let sourceMessageIDs = sourceValues.compactMap(UUID.init(uuidString:))
        guard sourceMessageIDs.count == sourceValues.count,
            Set(sourceMessageIDs).count == sourceMessageIDs.count
        else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "\(path).sourceMessageIDs")
        }

        let targetMemoryID = uuid(from: object["targetMemoryID"])
        let text = nullableString(from: object["text"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = nullableString(from: object["kind"]).flatMap(ContactMemoryKind.init(rawValue:))

        switch action {
        case .add:
            let expectedKeys: Set<String> = ["action", "text", "kind", "sourceMessageIDs"]
            guard Set(object.keys) == expectedKeys,
                let text, !text.isEmpty, text.count <= 240,
                kind != nil
            else {
                throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: path)
            }
        case .update:
            let expectedKeys: Set<String> = ["action", "targetMemoryID", "text", "kind", "sourceMessageIDs"]
            guard Set(object.keys) == expectedKeys,
                targetMemoryID != nil,
                let text, !text.isEmpty, text.count <= 240,
                kind != nil
            else {
                throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: path)
            }
        case .archive:
            let expectedKeys: Set<String> = ["action", "targetMemoryID", "sourceMessageIDs"]
            guard Set(object.keys) == expectedKeys, targetMemoryID != nil else {
                throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: path)
            }
        }

        return ContactMemoryChange(
            action: action,
            targetMemoryID: targetMemoryID,
            text: text,
            kind: kind,
            sourceMessageIDs: sourceMessageIDs
        )
    }

    private static func decodePersonaTraitChange(
        _ object: [String: Any], index: Int
    ) throws -> PersonaTraitChange {
        let path = "personaTraitChanges[\(index)]"
        guard Set(object.keys) == ["dimensionKey", "levelBand", "observation", "sourceMessageIDs"],
            let dimensionKey = object["dimensionKey"] as? String,
            let definition = PersonaStyleDimensionRegistry.definition(for: dimensionKey),
            definition.learnable,
            let observation = object["observation"] as? String,
            !observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            observation.count <= 180,
            let sourceValues = object["sourceMessageIDs"] as? [String],
            (1...10).contains(sourceValues.count)
        else { throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: path) }
        let levelBand: PersonaStyleBand?
        if object["levelBand"] is NSNull {
            levelBand = nil
        } else if let rawBand = object["levelBand"] as? String {
            levelBand = PersonaStyleBand(rawValue: rawBand)
        } else {
            levelBand = nil
        }
        guard definition.observationOnly == (levelBand == nil) else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "\(path).levelBand")
        }
        let ids = sourceValues.compactMap(UUID.init(uuidString:))
        guard ids.count == sourceValues.count, Set(ids).count == ids.count else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "\(path).sourceMessageIDs")
        }
        return PersonaTraitChange(
            dimensionKey: dimensionKey,
            levelBand: levelBand,
            observation: observation.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceMessageIDs: ids
        )
    }

    private static func uuid(from value: Any?) -> UUID? {
        guard let value = value as? String else { return nil }
        return UUID(uuidString: value)
    }

    private static func nullableString(from value: Any?) -> String? {
        value as? String
    }

}
