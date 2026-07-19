import Foundation

nonisolated struct SuggestedReplyPromptMessage: Codable, Equatable, Sendable {
    let id: UUID
    let sender: String
    let senderName: String?
    let text: String
    let timeLabel: String
}

nonisolated enum ChatMemoryChangeAction: String, Codable, CaseIterable, Equatable, Sendable {
    case add
    case update
    case archive
}

nonisolated struct ChatMemoryChange: Codable, Equatable, Sendable {
    let action: ChatMemoryChangeAction
    let targetMemoryID: UUID?
    let text: String?
    let sourceMessageIDs: [UUID]
}

nonisolated enum PersonaObservationChangeAction: String, Codable, CaseIterable, Equatable, Sendable
{
    case add
    case update
    case archive
}

nonisolated struct PersonaObservationChange: Codable, Equatable, Sendable {
    let action: PersonaObservationChangeAction
    let targetObservationID: UUID?
    let text: String?
    let sourceMessageIDs: [UUID]
}

nonisolated enum SuggestedReplySummaryMode: String, Codable, Equatable, Sendable {
    case unchanged
    case incremental
    case rebuild
}

nonisolated enum SuggestedReplyTask: String, Equatable, Sendable {
    case standard
    case drafting
    case personaStyleLearning
}

nonisolated struct SuggestedReplyGenerationRequest: Equatable, Sendable {
    let task: SuggestedReplyTask
    let chatMemories: [ChatMemory]
    let currentInteractionGoal: String
    let persona: PersonaPromptContext
    let personaLearningMessages: [SuggestedReplyPromptMessage]
    let existingHistorySummary: String
    let summaryMode: SuggestedReplySummaryMode
    let olderMessagesToSummarize: [SuggestedReplyPromptMessage]
    let recentMessages: [SuggestedReplyPromptMessage]
    let draftingInput: String?
    let previousConversationStrategy: String?
    let traceID: ImportTraceID

    init(
        task: SuggestedReplyTask,
        chatMemories: [ChatMemory],
        currentInteractionGoal: String,
        persona: PersonaPromptContext,
        personaLearningMessages: [SuggestedReplyPromptMessage],
        existingHistorySummary: String,
        summaryMode: SuggestedReplySummaryMode,
        olderMessagesToSummarize: [SuggestedReplyPromptMessage],
        recentMessages: [SuggestedReplyPromptMessage],
        draftingInput: String? = nil,
        previousConversationStrategy: String? = nil,
        traceID: ImportTraceID
    ) {
        self.task = task
        self.chatMemories = chatMemories
        self.currentInteractionGoal = currentInteractionGoal
        self.persona = persona
        self.personaLearningMessages = personaLearningMessages
        self.existingHistorySummary = existingHistorySummary
        self.summaryMode = summaryMode
        self.olderMessagesToSummarize = olderMessagesToSummarize
        self.recentMessages = recentMessages
        self.draftingInput = draftingInput
        self.previousConversationStrategy = previousConversationStrategy
        self.traceID = traceID
    }
}

nonisolated struct SuggestedReplyGenerationResult: Codable, Equatable, Sendable {
    let historySummary: String
    let replies: [String]
    let conversationStrategy: String
    let strategyRationale: String
    let memoryChanges: [ChatMemoryChange]
    let personaObservationChanges: [PersonaObservationChange]

    init(
        historySummary: String,
        replies: [String],
        conversationStrategy: String,
        strategyRationale: String,
        memoryChanges: [ChatMemoryChange] = [],
        personaObservationChanges: [PersonaObservationChange] = []
    ) {
        self.historySummary = historySummary
        self.replies = replies
        self.conversationStrategy = conversationStrategy
        self.strategyRationale = strategyRationale
        self.memoryChanges = memoryChanges
        self.personaObservationChanges = personaObservationChanges
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
        task: SuggestedReplyTask,
        historySummaryFallback: String? = nil
    ) throws -> SuggestedReplyGenerationResult {
        if let finishReason, finishReason != "stop" {
            let kind: StructuredOutputFailureKind =
                finishReason == "length"
                ? .truncatedResponse : .schemaMismatch
            throw StructuredOutputFailure(kind: kind, codingPath: "finish_reason")
        }
        let cleaned = clean(content)
        guard let data = cleaned.data(using: .utf8), !cleaned.isEmpty else {
            throw StructuredOutputFailure(kind: .emptyResponse, codingPath: nil)
        }
        let object: [String: Any]
        do {
            object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw StructuredOutputFailure(kind: .invalidJSON, codingPath: nil)
        }
        guard !object.isEmpty else { throw schema("root") }

        let expectedKeys: Set<String>
        switch task {
        case .standard:
            expectedKeys = [
                "historySummary", "replies", "conversationStrategy", "strategyRationale",
                "memoryChanges", "personaObservationChanges"
            ]
        case .drafting:
            expectedKeys = ["replies", "conversationStrategy", "strategyRationale"]
        case .personaStyleLearning:
            expectedKeys = ["personaObservationChanges"]
        }
        guard Set(object.keys) == expectedKeys else { throw schema("root") }

        let summary: String
        if task == .standard {
            let summaryValue = object["historySummary"]
            if summaryValue is NSNull {
                guard let historySummaryFallback else { throw schema("historySummary") }
                summary = historySummaryFallback
            } else if let value = summaryValue as? String {
                summary = value.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                throw schema("historySummary")
            }
            guard summary.count <= 2_000 else { throw schema("historySummary") }
        } else {
            summary = historySummaryFallback ?? ""
        }

        let replies: [String]
        let conversationStrategy: String
        let strategyRationale: String
        if task == .standard || task == .drafting {
            guard let values = object["replies"] as? [String] else { throw schema("replies") }
            replies = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard replies.count == 2,
                replies.allSatisfy({ !$0.isEmpty && $0.count <= 500 }),
                Set(replies.map { $0.lowercased() }).count == 2
            else { throw schema("replies") }
            conversationStrategy = try requiredString(
                from: object["conversationStrategy"], path: "conversationStrategy", maxLength: 500)
            strategyRationale = try requiredString(
                from: object["strategyRationale"], path: "strategyRationale", maxLength: 700)
        } else {
            replies = []
            conversationStrategy = ""
            strategyRationale = ""
        }

        let memories: [ChatMemoryChange]
        if task == .standard {
            guard let values = object["memoryChanges"] as? [[String: Any]], values.count <= 8 else {
                throw schema("memoryChanges")
            }
            memories = try values.enumerated().map {
                try decodeMemoryChange($0.element, index: $0.offset)
            }
        } else {
            memories = []
        }

        let observations: [PersonaObservationChange]
        if task == .standard || task == .personaStyleLearning {
            guard let values = object["personaObservationChanges"] as? [[String: Any]],
                values.count <= PersonaLimits.maximumActiveObservations
            else { throw schema("personaObservationChanges") }
            observations = try values.enumerated().map {
                try decodeObservationChange($0.element, index: $0.offset)
            }
        } else {
            observations = []
        }

        return SuggestedReplyGenerationResult(
            historySummary: summary, replies: replies,
            conversationStrategy: conversationStrategy,
            strategyRationale: strategyRationale,
            memoryChanges: memories, personaObservationChanges: observations
        )
    }

    private static func decodeMemoryChange(_ object: [String: Any], index: Int) throws
        -> ChatMemoryChange
    {
        let path = "memoryChanges[\(index)]"
        guard Set(object.keys) == ["action", "targetMemoryID", "text", "evidenceMessageIDs"],
            let rawAction = object["action"] as? String,
            let action = ChatMemoryChangeAction(rawValue: rawAction),
            let sourceValues = object["evidenceMessageIDs"] as? [String],
            (1...3).contains(sourceValues.count)
        else { throw schema(path) }
        let ids = try decodeIDs(sourceValues, path: "\(path).evidenceMessageIDs")
        let target = uuid(from: object["targetMemoryID"])
        let text = nullableString(from: object["text"])
        try validate(action: action.rawValue, target: target, text: text, path: path)
        return ChatMemoryChange(
            action: action, targetMemoryID: target, text: text, sourceMessageIDs: ids)
    }

    private static func decodeObservationChange(_ object: [String: Any], index: Int) throws
        -> PersonaObservationChange
    {
        let path = "personaObservationChanges[\(index)]"
        guard Set(object.keys) == ["action", "targetObservationID", "text", "evidenceMessageIDs"],
            let rawAction = object["action"] as? String,
            let action = PersonaObservationChangeAction(rawValue: rawAction),
            let sourceValues = object["evidenceMessageIDs"] as? [String],
            (2...10).contains(sourceValues.count)
        else { throw schema(path) }
        let ids = try decodeIDs(sourceValues, path: "\(path).evidenceMessageIDs")
        let target = uuid(from: object["targetObservationID"])
        let text = nullableString(from: object["text"])
        try validate(action: action.rawValue, target: target, text: text, path: path)
        return PersonaObservationChange(
            action: action, targetObservationID: target, text: text, sourceMessageIDs: ids)
    }

    private static func validate(action: String, target: UUID?, text: String?, path: String) throws
    {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case "add":
            guard target == nil, let value, !value.isEmpty, value.count <= 240 else {
                throw schema(path)
            }
        case "update":
            guard target != nil, let value, !value.isEmpty, value.count <= 240 else {
                throw schema(path)
            }
        case "archive": guard target != nil, text == nil else { throw schema(path) }
        default: throw schema(path)
        }
    }

    private static func decodeIDs(_ values: [String], path: String) throws -> [UUID] {
        let ids = values.compactMap(UUID.init(uuidString:))
        guard ids.count == values.count, Set(ids).count == ids.count else { throw schema(path) }
        return ids
    }

    private static func clean(_ content: String?) -> String {
        content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func uuid(from value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }

    private static func nullableString(from value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func requiredString(from value: Any?, path: String, maxLength: Int) throws
        -> String
    {
        guard let string = value as? String else { throw schema(path) }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { throw schema(path) }
        return trimmed
    }

    private static func schema(_ path: String) -> StructuredOutputFailure {
        StructuredOutputFailure(kind: .schemaMismatch, codingPath: path)
    }
}
