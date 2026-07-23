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
    let olderMessagesToSummarize: [SuggestedReplyPromptMessage]
    let recentMessages: [SuggestedReplyPromptMessage]
    let draftingInput: String?
    let previousConversationStrategy: String?
    let presentationLanguageIdentifier: String
    let traceID: ImportTraceID

    init(
        task: SuggestedReplyTask,
        chatMemories: [ChatMemory],
        currentInteractionGoal: String,
        persona: PersonaPromptContext,
        personaLearningMessages: [SuggestedReplyPromptMessage],
        existingHistorySummary: String,
        olderMessagesToSummarize: [SuggestedReplyPromptMessage],
        recentMessages: [SuggestedReplyPromptMessage],
        draftingInput: String? = nil,
        previousConversationStrategy: String? = nil,
        presentationLanguageIdentifier: String,
        traceID: ImportTraceID
    ) {
        self.task = task
        self.chatMemories = chatMemories
        self.currentInteractionGoal = currentInteractionGoal
        self.persona = persona
        self.personaLearningMessages = personaLearningMessages
        self.existingHistorySummary = existingHistorySummary
        self.olderMessagesToSummarize = olderMessagesToSummarize
        self.recentMessages = recentMessages
        self.draftingInput = draftingInput
        self.previousConversationStrategy = previousConversationStrategy
        self.presentationLanguageIdentifier = presentationLanguageIdentifier
        self.traceID = traceID
    }
}

nonisolated struct SuggestedReplyGenerationResult: Codable, Equatable, Sendable {
    let historySummary: String?
    let replies: [String]
    let conversationStrategy: String
    let strategyRationale: String
    let memoryChanges: [ChatMemoryChange]
    let personaObservationChanges: [PersonaObservationChange]
    let personaObservationChangesAvailable: Bool

    init(
        historySummary: String?,
        replies: [String],
        conversationStrategy: String,
        strategyRationale: String,
        memoryChanges: [ChatMemoryChange] = [],
        personaObservationChanges: [PersonaObservationChange] = [],
        personaObservationChangesAvailable: Bool = true
    ) {
        self.historySummary = historySummary
        self.replies = replies
        self.conversationStrategy = conversationStrategy
        self.strategyRationale = strategyRationale
        self.memoryChanges = memoryChanges
        self.personaObservationChanges = personaObservationChanges
        self.personaObservationChangesAvailable = personaObservationChangesAvailable
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
        task: SuggestedReplyTask
    ) throws -> SuggestedReplyGenerationResult {
        try decodeResult(content: content, finishReason: finishReason, task: task).value
    }

    static func decodeResult(
        content: String?,
        finishReason: String?,
        task: SuggestedReplyTask
    ) throws -> StructuredOutputDecodingResult<SuggestedReplyGenerationResult> {
        if let finishReason, finishReason != "stop" {
            let kind: StructuredOutputFailureKind =
                finishReason == "length"
                ? .truncatedResponse : .schemaMismatch
            throw StructuredOutputFailure(kind: kind, codingPath: "finish_reason")
        }
        let normalized = try StructuredOutputJSONNormalizer.decodeObject(from: content)
        let object = normalized.object
        guard !object.isEmpty else { throw schema("root") }
        var recovered = normalized.recovered

        let knownKeys: Set<String>
        switch task {
        case .standard:
            knownKeys = [
                "historySummary",
                "replies", "conversationStrategy", "strategyRationale", "memoryChanges",
                "personaObservationChanges"
            ]
        case .drafting:
            knownKeys = ["replies", "conversationStrategy", "strategyRationale"]
        case .personaStyleLearning:
            knownKeys = ["personaObservationChanges"]
        }
        if !Set(object.keys).subtracting(knownKeys).isEmpty {
            recovered = true
        }

        let summary: String?
        if task == .standard {
            if let value = object["historySummary"] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed.count <= 2_000 {
                    summary = trimmed
                } else {
                    summary = nil
                    recovered = true
                }
            } else {
                summary = nil
                if object["historySummary"] == nil || !(object["historySummary"] is NSNull) {
                    recovered = true
                }
            }
        } else {
            summary = nil
        }

        let replies: [String]
        let conversationStrategy: String
        let strategyRationale: String
        if task == .standard || task == .drafting {
            guard let values = object["replies"] as? [Any] else { throw schema("replies") }
            var seen: Set<String> = []
            var validReplies: [String] = []
            for value in values {
                guard let string = value as? String else {
                    recovered = true
                    continue
                }
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                let identity = trimmed.lowercased()
                guard !trimmed.isEmpty, trimmed.count <= 500, seen.insert(identity).inserted else {
                    recovered = true
                    continue
                }
                if validReplies.count < 2 {
                    validReplies.append(trimmed)
                } else {
                    recovered = true
                }
            }
            guard validReplies.count == 2 else { throw schema("replies") }
            replies = validReplies
            (conversationStrategy, recovered) = recoveredString(
                from: object["conversationStrategy"], maxLength: 500, recovered: recovered)
            (strategyRationale, recovered) = recoveredString(
                from: object["strategyRationale"], maxLength: 700, recovered: recovered)
        } else {
            replies = []
            conversationStrategy = ""
            strategyRationale = ""
        }

        let memories: [ChatMemoryChange]
        if task == .standard {
            if let values = object["memoryChanges"] as? [Any] {
                var decoded: [ChatMemoryChange] = []
                for (index, value) in values.enumerated() {
                    guard decoded.count < 8, let item = value as? [String: Any],
                        let change = try? decodeMemoryChange(item, index: index)
                    else {
                        recovered = true
                        continue
                    }
                    if !Set(item.keys).subtracting([
                        "action", "targetMemoryID", "text", "evidenceMessageIDs"
                    ]).isEmpty {
                        recovered = true
                    }
                    decoded.append(change)
                }
                memories = decoded
            } else {
                memories = []
                recovered = true
            }
        } else {
            memories = []
        }

        let observations: [PersonaObservationChange]
        let observationsAvailable: Bool
        if task == .standard || task == .personaStyleLearning {
            if let values = object["personaObservationChanges"] as? [Any] {
                var decoded: [PersonaObservationChange] = []
                for (index, value) in values.enumerated() {
                    guard decoded.count < PersonaLimits.maximumActiveObservations,
                        let item = value as? [String: Any],
                        let change = try? decodeObservationChange(item, index: index)
                    else {
                        recovered = true
                        continue
                    }
                    if !Set(item.keys).subtracting([
                        "action", "targetObservationID", "text", "evidenceMessageIDs"
                    ]).isEmpty {
                        recovered = true
                    }
                    decoded.append(change)
                }
                if task == .personaStyleLearning, !values.isEmpty, decoded.isEmpty {
                    throw schema("personaObservationChanges")
                }
                observations = decoded
                observationsAvailable = true
            } else if task == .personaStyleLearning {
                throw schema("personaObservationChanges")
            } else {
                observations = []
                observationsAvailable = false
                recovered = true
            }
        } else {
            observations = []
            observationsAvailable = false
        }

        return StructuredOutputDecodingResult(
            value: SuggestedReplyGenerationResult(
                historySummary: summary, replies: replies,
                conversationStrategy: conversationStrategy,
                strategyRationale: strategyRationale,
                memoryChanges: memories, personaObservationChanges: observations,
                personaObservationChangesAvailable: observationsAvailable
            ),
            recovered: recovered
        )
    }

    private static func decodeMemoryChange(_ object: [String: Any], index: Int) throws
        -> ChatMemoryChange
    {
        let path = "memoryChanges[\(index)]"
        guard let rawAction = object["action"] as? String,
            let action = ChatMemoryChangeAction(rawValue: rawAction),
            let sourceValues = object["evidenceMessageIDs"] as? [String],
            (1...3).contains(sourceValues.count)
        else { throw schema(path) }
        let ids = try decodeIDs(sourceValues, path: "\(path).evidenceMessageIDs")
        let target = try nullableUUID(from: object["targetMemoryID"], path: path)
        let text = try nullableString(from: object["text"], path: path)
        try validate(action: action.rawValue, target: target, text: text, path: path)
        return ChatMemoryChange(
            action: action, targetMemoryID: target, text: text, sourceMessageIDs: ids)
    }

    private static func decodeObservationChange(_ object: [String: Any], index: Int) throws
        -> PersonaObservationChange
    {
        let path = "personaObservationChanges[\(index)]"
        guard let rawAction = object["action"] as? String,
            let action = PersonaObservationChangeAction(rawValue: rawAction),
            let sourceValues = object["evidenceMessageIDs"] as? [String],
            (2...10).contains(sourceValues.count)
        else { throw schema(path) }
        let ids = try decodeIDs(sourceValues, path: "\(path).evidenceMessageIDs")
        let target = try nullableUUID(from: object["targetObservationID"], path: path)
        let text = try nullableString(from: object["text"], path: path)
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

    private static func nullableUUID(from value: Any?, path: String) throws -> UUID? {
        if value == nil || value is NSNull { return nil }
        guard let string = value as? String, let id = UUID(uuidString: string) else {
            throw schema(path)
        }
        return id
    }

    private static func nullableString(from value: Any?, path: String) throws -> String? {
        if value == nil || value is NSNull { return nil }
        guard let string = value as? String else { throw schema(path) }
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func recoveredString(
        from value: Any?,
        maxLength: Int,
        recovered: Bool
    ) -> (String, Bool) {
        guard let string = value as? String else { return ("", true) }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return ("", true) }
        return (trimmed, recovered)
    }

    private static func schema(_ path: String) -> StructuredOutputFailure {
        StructuredOutputFailure(kind: .schemaMismatch, codingPath: path)
    }
}
