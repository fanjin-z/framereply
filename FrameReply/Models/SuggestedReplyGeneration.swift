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

nonisolated struct PersonalInfoChange: Codable, Equatable, Sendable {
    let action: ChatMemoryChangeAction
    let targetFactID: UUID?
    let text: String?
    let sourceMessageIDs: [UUID]
}

nonisolated enum SuggestedReplyTask: String, Equatable, Sendable {
    case standard
    case drafting
    case personaStyleLearning
}

nonisolated enum SuggestedReplyTextLimits {
    static let conversationStrategyMaximumCodePoints = 300
    static let strategyRationaleMaximumCodePoints = 450
}

nonisolated struct SuggestedReplyGenerationRequest: Equatable, Sendable {
    let task: SuggestedReplyTask
    let chatMemories: [ChatMemory]
    let currentInteractionGoal: String
    let persona: PersonaPromptContext
    let personaLearningMessages: [SuggestedReplyPromptMessage]
    let personalInfo: PersonalInfoPromptContext
    let personalInfoLearningEnabled: Bool
    let existingHistorySummary: String
    let olderMessagesToSummarize: [SuggestedReplyPromptMessage]
    let recentMessages: [SuggestedReplyPromptMessage]
    let draftingInput: String?
    let previousConversationStrategy: String?
    /// Supported FrameReply localization tag, such as "en" or "zh-Hans".
    let appLanguage: String
    let traceID: ImportTraceID

    init(
        task: SuggestedReplyTask,
        chatMemories: [ChatMemory],
        currentInteractionGoal: String,
        persona: PersonaPromptContext,
        personaLearningMessages: [SuggestedReplyPromptMessage],
        personalInfo: PersonalInfoPromptContext = .empty,
        personalInfoLearningEnabled: Bool = false,
        existingHistorySummary: String,
        olderMessagesToSummarize: [SuggestedReplyPromptMessage],
        recentMessages: [SuggestedReplyPromptMessage],
        draftingInput: String? = nil,
        previousConversationStrategy: String? = nil,
        appLanguage: String,
        traceID: ImportTraceID
    ) {
        self.task = task
        self.chatMemories = chatMemories
        self.currentInteractionGoal = currentInteractionGoal
        self.persona = persona
        self.personaLearningMessages = personaLearningMessages
        self.personalInfo = personalInfo
        self.personalInfoLearningEnabled = personalInfoLearningEnabled
        self.existingHistorySummary = existingHistorySummary
        self.olderMessagesToSummarize = olderMessagesToSummarize
        self.recentMessages = recentMessages
        self.draftingInput = draftingInput
        self.previousConversationStrategy = previousConversationStrategy
        self.appLanguage = appLanguage
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
    let personalInfoChanges: [PersonalInfoChange]

    init(
        historySummary: String?,
        replies: [String],
        conversationStrategy: String,
        strategyRationale: String,
        memoryChanges: [ChatMemoryChange] = [],
        personaObservationChanges: [PersonaObservationChange] = [],
        personaObservationChangesAvailable: Bool = true,
        personalInfoChanges: [PersonalInfoChange] = []
    ) {
        self.historySummary = historySummary
        self.replies = replies
        self.conversationStrategy = conversationStrategy
        self.strategyRationale = strategyRationale
        self.memoryChanges = memoryChanges
        self.personaObservationChanges = personaObservationChanges
        self.personaObservationChangesAvailable = personaObservationChangesAvailable
        self.personalInfoChanges = personalInfoChanges
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
    private struct DroppedOverlongField: Error {
        let recovery: StructuredOutputFieldRecovery
    }

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
        var fieldRecoveries: [StructuredOutputFieldRecovery] = []

        let knownKeys: Set<String>
        switch task {
        case .standard:
            knownKeys = [
                "historySummary",
                "replies", "conversationStrategy", "strategyRationale", "memoryChanges",
                "personaObservationChanges", "personalInfoChanges"
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
                if !trimmed.isEmpty, trimmed.unicodeScalars.count <= 2_000 {
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
            guard values.isEmpty || values.count == 2 else { throw schema("replies") }
            var seen: Set<String> = []
            var validReplies: [String] = []
            for value in values {
                guard let string = value as? String else { throw schema("replies") }
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                let identity = trimmed.lowercased()
                guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= 500,
                    seen.insert(identity).inserted
                else {
                    throw schema("replies")
                }
                validReplies.append(trimmed)
            }
            replies = validReplies
            let strategy = try requiredBoundedString(
                from: object["conversationStrategy"],
                maximumCodePoints:
                    SuggestedReplyTextLimits.conversationStrategyMaximumCodePoints,
                path: "conversationStrategy"
            )
            conversationStrategy = strategy.value
            if let recovery = strategy.recovery {
                fieldRecoveries.append(recovery)
            }
            let rationale = try requiredBoundedString(
                from: object["strategyRationale"],
                maximumCodePoints:
                    SuggestedReplyTextLimits.strategyRationaleMaximumCodePoints,
                path: "strategyRationale"
            )
            strategyRationale = rationale.value
            if let recovery = rationale.recovery {
                fieldRecoveries.append(recovery)
            }
            if !fieldRecoveries.isEmpty {
                recovered = true
            }
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
                    guard decoded.count < 8, let item = value as? [String: Any] else {
                        recovered = true
                        continue
                    }
                    let change: ChatMemoryChange
                    do {
                        change = try decodeMemoryChange(item, index: index)
                    } catch let dropped as DroppedOverlongField {
                        fieldRecoveries.append(dropped.recovery)
                        recovered = true
                        continue
                    } catch {
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
                var hasMalformedObservationChange = false
                for (index, value) in values.enumerated() {
                    guard decoded.count < PersonaLimits.maximumActiveObservations,
                        let item = value as? [String: Any]
                    else {
                        hasMalformedObservationChange = true
                        recovered = true
                        continue
                    }
                    let change: PersonaObservationChange
                    do {
                        change = try decodeObservationChange(item, index: index)
                    } catch let dropped as DroppedOverlongField {
                        fieldRecoveries.append(dropped.recovery)
                        recovered = true
                        continue
                    } catch {
                        hasMalformedObservationChange = true
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
                if task == .personaStyleLearning, !values.isEmpty, decoded.isEmpty,
                    hasMalformedObservationChange
                {
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

        let personalInfoChanges: [PersonalInfoChange]
        if task == .standard {
            if let values = object["personalInfoChanges"] as? [Any] {
                var decoded: [PersonalInfoChange] = []
                for (index, value) in values.enumerated() {
                    guard decoded.count < PersonalInfoLimits.maximumChangesPerGeneration,
                        let item = value as? [String: Any]
                    else {
                        recovered = true
                        continue
                    }
                    do {
                        decoded.append(try decodePersonalInfoChange(item, index: index))
                    } catch let dropped as DroppedOverlongField {
                        fieldRecoveries.append(dropped.recovery)
                        recovered = true
                        continue
                    } catch {
                        recovered = true
                        continue
                    }
                    if !Set(item.keys).subtracting([
                        "action", "targetFactID", "text", "evidenceMessageIDs"
                    ]).isEmpty {
                        recovered = true
                    }
                }
                personalInfoChanges = decoded
            } else {
                personalInfoChanges = []
                recovered = true
            }
        } else {
            personalInfoChanges = []
        }

        return StructuredOutputDecodingResult(
            value: SuggestedReplyGenerationResult(
                historySummary: summary, replies: replies,
                conversationStrategy: conversationStrategy,
                strategyRationale: strategyRationale,
                memoryChanges: memories, personaObservationChanges: observations,
                personaObservationChangesAvailable: observationsAvailable,
                personalInfoChanges: personalInfoChanges
            ),
            recovered: recovered,
            fieldRecoveries: fieldRecoveries
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
        try validate(
            action: action.rawValue,
            target: target,
            text: text,
            maximumTextCodePoints: ChatMemoryLimits.maximumAITextCodePoints,
            path: path
        )
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
        try validate(
            action: action.rawValue,
            target: target,
            text: text,
            maximumTextCodePoints: PersonaLimits.maximumObservationTextCodePoints,
            path: path
        )
        return PersonaObservationChange(
            action: action, targetObservationID: target, text: text, sourceMessageIDs: ids)
    }

    private static func decodePersonalInfoChange(_ object: [String: Any], index: Int) throws
        -> PersonalInfoChange
    {
        let path = "personalInfoChanges[\(index)]"
        guard let rawAction = object["action"] as? String,
            let action = ChatMemoryChangeAction(rawValue: rawAction),
            let sourceValues = object["evidenceMessageIDs"] as? [String],
            (1...3).contains(sourceValues.count)
        else { throw schema(path) }
        let ids = try decodeIDs(sourceValues, path: "\(path).evidenceMessageIDs")
        let target = try nullableUUID(from: object["targetFactID"], path: path)
        let text = try nullableString(from: object["text"], path: path)
        try validate(
            action: action.rawValue,
            target: target,
            text: text,
            maximumTextCodePoints: PersonalInfoLimits.maximumTextCodePoints,
            path: path
        )
        return PersonalInfoChange(
            action: action, targetFactID: target, text: text, sourceMessageIDs: ids
        )
    }

    private static func validate(
        action: String,
        target: UUID?,
        text: String?,
        maximumTextCodePoints: Int,
        path: String
    ) throws {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case "add":
            guard target == nil, let value, !value.isEmpty else { throw schema(path) }
            try validateMaximumCodePoints(
                value, maximumCodePoints: maximumTextCodePoints, path: "\(path).text")
        case "update":
            guard target != nil, let value, !value.isEmpty else { throw schema(path) }
            try validateMaximumCodePoints(
                value, maximumCodePoints: maximumTextCodePoints, path: "\(path).text")
        case "archive": guard target != nil, text == nil else { throw schema(path) }
        default: throw schema(path)
        }
    }

    private static func validateMaximumCodePoints(
        _ value: String,
        maximumCodePoints: Int,
        path: String
    ) throws {
        let count = value.unicodeScalars.count
        guard count > maximumCodePoints else { return }
        throw DroppedOverlongField(
            recovery: StructuredOutputFieldRecovery(
                path: path,
                originalCodePointCount: count,
                finalCodePointCount: 0
            )
        )
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

    private struct BoundedStringResult {
        let value: String
        let recovery: StructuredOutputFieldRecovery?
    }

    private static func requiredBoundedString(
        from value: Any?,
        maximumCodePoints: Int,
        path: String
    ) throws -> BoundedStringResult {
        guard let string = value as? String else { throw schema(path) }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw schema(path) }

        let originalCount = trimmed.unicodeScalars.count
        guard originalCount > maximumCodePoints else {
            return BoundedStringResult(value: trimmed, recovery: nil)
        }

        let shortened = shorten(
            trimmed,
            maximumCodePoints: maximumCodePoints
        )
        guard !shortened.isEmpty else { throw schema(path) }
        return BoundedStringResult(
            value: shortened,
            recovery: StructuredOutputFieldRecovery(
                path: path,
                originalCodePointCount: originalCount,
                finalCodePointCount: shortened.unicodeScalars.count
            )
        )
    }

    private static func shorten(_ value: String, maximumCodePoints: Int) -> String {
        let hardPrefix = graphemeSafePrefix(value, maximumCodePoints: maximumCodePoints)
        let sentenceTerminators: Set<Character> = [".", "!", "?", "。", "！", "？"]
        if let sentenceEnd = hardPrefix.lastIndex(where: sentenceTerminators.contains) {
            let end = hardPrefix.index(after: sentenceEnd)
            let sentence = hardPrefix[..<end]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                return sentence
            }
        }

        let ellipsis = "…"
        let wordPrefix = graphemeSafePrefix(
            value,
            maximumCodePoints: max(0, maximumCodePoints - ellipsis.unicodeScalars.count)
        )
        if let boundary = wordPrefix.lastIndex(where: { $0.isWhitespace }) {
            let atBoundary = wordPrefix[..<boundary]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !atBoundary.isEmpty {
                return atBoundary + ellipsis
            }
        }

        return hardPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func graphemeSafePrefix(
        _ value: String,
        maximumCodePoints: Int
    ) -> String {
        guard maximumCodePoints > 0 else { return "" }
        var result = ""
        var count = 0
        for character in value {
            let characterCount = character.unicodeScalars.count
            guard count + characterCount <= maximumCodePoints else { break }
            result.append(character)
            count += characterCount
        }
        return result
    }

    private static func schema(_ path: String) -> StructuredOutputFailure {
        StructuredOutputFailure(kind: .schemaMismatch, codingPath: path)
    }
}
