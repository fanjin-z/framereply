import CryptoKit
import Foundation

nonisolated enum SuggestedReplyGenerationSource: String, Codable, Equatable, Sendable {
    case generated
    case cached
}

nonisolated struct SuggestedRepliesOutcome: Equatable, Sendable {
    let replies: [String]
    let conversationStrategy: String
    let strategyRationale: String
    let source: SuggestedReplyGenerationSource

    init(
        replies: [String],
        conversationStrategy: String = "",
        strategyRationale: String = "",
        source: SuggestedReplyGenerationSource
    ) {
        self.replies = replies
        self.conversationStrategy = conversationStrategy
        self.strategyRationale = strategyRationale
        self.source = source
    }
}

nonisolated enum SuggestedRepliesError: LocalizedError, Sendable {
    case noActiveProvider
    case missingAPIKey
    case consentRequired
    case noMessages
    case chatNotFound
    case unsupportedProvider
    case invalidProviderResponse

    var errorDescription: String? {
        switch self {
        case .noActiveProvider:
            "Connect and select a model provider to generate replies."
        case .missingAPIKey:
            "The selected provider API key is unavailable. Reconnect it in Settings."
        case .consentRequired:
            "Allow provider sharing in Settings → Privacy & Data first."
        case .noMessages:
            "Import at least one chat message before generating replies."
        case .chatNotFound:
            "This chat is no longer available."
        case .unsupportedProvider:
            "The selected provider cannot generate suggested replies."
        case .invalidProviderResponse:
            "The provider could not generate replies in the expected format. Try again."
        }
    }

    var code: String {
        switch self {
        case .noActiveProvider: "no_provider"
        case .missingAPIKey: "missing_api_key"
        case .consentRequired: "provider_consent_required"
        case .noMessages: "no_messages"
        case .chatNotFound: "chat_not_found"
        case .unsupportedProvider: "unsupported_provider"
        case .invalidProviderResponse: "reply_schema_mismatch"
        }
    }

    init(_ error: AIServiceError) {
        switch error {
        case .noActiveProvider:
            self = .noActiveProvider
        case .missingAPIKey:
            self = .missingAPIKey
        case .consentRequired:
            self = .consentRequired
        case .unsupportedProvider, .unsupportedCapability:
            self = .unsupportedProvider
        }
    }
}

@MainActor
final class SuggestedRepliesCoordinator {
    static let recentMessageLimit = 20

    private let aiService: any AIServiceProviding
    private let repository: ChatRepository

    convenience init() {
        self.init(providerStore: ProviderStore())
    }

    convenience init(providerStore: any ProviderConfigurationProviding) {
        self.init(
            aiService: AIService(providerConfiguration: providerStore),
            repository: ChatRepository()
        )
    }

    init(
        aiService: any AIServiceProviding,
        repository: ChatRepository
    ) {
        self.aiService = aiService
        self.repository = repository
    }

    func cachedReplies(chatID: String) throws -> SuggestedRepliesOutcome? {
        guard let providerContext = try? aiService.activeContext(requiring: .suggestedReplies),
            try repository.chat(id: chatID) != nil
        else {
            return nil
        }
        let messages = try repository.messages(chatID: chatID)
        guard !messages.isEmpty else { return nil }

        let chatContext = try repository.chatContextValue(chatID: chatID)
        let persona = try repository.personaPromptContext(personaID: chatContext.personaID)
        let learningMessages = try repository.personaLearningMessages(
            chatID: chatID,
            personaID: persona.id,
            assignedAt: chatContext.personaAssignedAt
        )
        guard let cache = try repository.suggestedReplyCache(chatID: chatID) else {
            return nil
        }
        let inputFingerprint = fingerprint(
            messages: messages,
            chatContext: chatContext,
            persona: persona,
            learningMessageIDs: learningMessages.map(\.id),
            provider: providerContext.platform,
            model: providerContext.effectiveModel
        )
        guard cache.inputFingerprint == inputFingerprint,
            cache.promptVersion == SuggestedReplyPrompt.version,
            cache.replies.count == 2
        else {
            return nil
        }
        return SuggestedRepliesOutcome(
            replies: cache.replies,
            conversationStrategy: cache.conversationStrategy,
            strategyRationale: cache.strategyRationale,
            source: .cached
        )
    }

    func generate(
        chatID: String,
        draftingInput: String? = nil,
        force: Bool = false,
        traceID: ImportTraceID = ImportTraceID()
    ) async throws -> SuggestedRepliesOutcome {
        let draftingInput = draftingInput?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(2_000)
        let oneUseInput = draftingInput.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
        let providerContext: AIProviderExecutionContext
        do {
            providerContext = try aiService.activeContext(requiring: .suggestedReplies)
        } catch let error as AIServiceError {
            throw SuggestedRepliesError(error)
        }
        guard try repository.chat(id: chatID) != nil else {
            throw SuggestedRepliesError.chatNotFound
        }

        let messages = try repository.messages(chatID: chatID)
        guard !messages.isEmpty else {
            throw SuggestedRepliesError.noMessages
        }

        let chatContext = try repository.chatContextValue(chatID: chatID)
        let persona = try repository.personaPromptContext(personaID: chatContext.personaID)
        let learningMessages = try repository.personaLearningMessages(
            chatID: chatID,
            personaID: persona.id,
            assignedAt: chatContext.personaAssignedAt
        )
        let cache = try repository.suggestedReplyCache(chatID: chatID)
        let replyModel = providerContext.effectiveModel
        let inputFingerprint = fingerprint(
            messages: messages,
            chatContext: chatContext,
            persona: persona,
            learningMessageIDs: learningMessages.map(\.id),
            provider: providerContext.platform,
            model: replyModel
        )

        if oneUseInput == nil, !force,
            let cache,
            cache.inputFingerprint == inputFingerprint,
            cache.promptVersion == SuggestedReplyPrompt.version,
            cache.replies.count == 2
        {
            return SuggestedRepliesOutcome(
                replies: cache.replies,
                conversationStrategy: cache.conversationStrategy,
                strategyRationale: cache.strategyRationale,
                source: .cached
            )
        }

        let olderCount = max(0, messages.count - Self.recentMessageLimit)
        let olderMessages = Array(messages.prefix(olderCount))
        let recentMessages = Array(messages.suffix(Self.recentMessageLimit))
        let summaryPlan = makeSummaryPlan(olderMessages: olderMessages, cache: cache)
        let previousConversationStrategy = cache?.conversationStrategy
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let strategyContext = previousConversationStrategy.flatMap { $0.isEmpty ? nil : $0 }
        let request = SuggestedReplyGenerationRequest(
            task: oneUseInput == nil ? .standard : .drafting,
            chatMemories: chatContext.chatMemories.filter { $0.status == .active },
            currentInteractionGoal: chatContext.currentInteractionGoal,
            persona: persona,
            personaLearningMessages: learningMessages.map(promptMessage),
            existingHistorySummary: summaryPlan.existingSummary,
            summaryMode: summaryPlan.mode,
            olderMessagesToSummarize: summaryPlan.messages.map(promptMessage),
            recentMessages: recentMessages.map(promptMessage),
            draftingInput: oneUseInput,
            previousConversationStrategy: strategyContext,
            traceID: traceID
        )

        let generated: SuggestedReplyGenerationResult
        do {
            generated = try await aiService.generateSuggestedReplies(
                request,
                using: providerContext
            )
        } catch let error as AIServiceError {
            throw SuggestedRepliesError(error)
        } catch let error as ProviderConnectionError {
            if case .structuredOutput = error {
                throw SuggestedRepliesError.invalidProviderResponse
            }
            throw error
        }
        try Task.checkCancellation()
        guard
            try inputIsCurrent(
                chatID: chatID,
                expectedFingerprint: inputFingerprint,
                providerContext: providerContext
            )
        else {
            throw CancellationError()
        }

        let historySummary: String
        switch summaryPlan.mode {
        case .unchanged:
            historySummary = summaryPlan.existingSummary
        case .incremental, .rebuild:
            historySummary = olderMessages.isEmpty ? "" : generated.historySummary
        }

        let otherParticipantEvidenceMessageIDs = Set(
            (summaryPlan.messages + recentMessages)
                .filter { $0.senderKind == "other_participant" }
                .map(\.id)
        )
        var reconciledContext = chatContext
        reconciledContext.chatMemories = ChatMemoryReconciler.reconcile(
            memories: chatContext.chatMemories,
            changes: generated.memoryChanges,
            allowedOtherParticipantSourceMessageIDs: otherParticipantEvidenceMessageIDs
        )
        let learningMessageIDs = Set(learningMessages.map(\.id))
        let validObservationChanges = generated.personaObservationChanges.filter {
            $0.sourceMessageIDs.count >= 2
                && $0.sourceMessageIDs.allSatisfy(learningMessageIDs.contains)
        }

        // Input-specific output cannot affect summaries, memory, or persona
        // learning. Cache only its replies so the app can show the same result.
        if oneUseInput != nil {
            try repository.saveSuggestedRepliesOnly(
                chatID: chatID,
                replies: generated.replies,
                conversationStrategy: generated.conversationStrategy,
                strategyRationale: generated.strategyRationale,
                inputFingerprint: inputFingerprint,
                promptVersion: SuggestedReplyPrompt.version
            )
            return SuggestedRepliesOutcome(
                replies: generated.replies,
                conversationStrategy: generated.conversationStrategy,
                strategyRationale: generated.strategyRationale,
                source: .generated
            )
        }

        let persistedFingerprint = fingerprint(
            messages: messages,
            chatContext: reconciledContext,
            persona: try repository.projectedPersonaPromptContext(
                personaID: persona.id, changes: validObservationChanges
            ),
            learningMessageIDs: [],
            provider: providerContext.platform,
            model: replyModel
        )

        try repository.saveSuggestedReplyGeneration(
            chatID: chatID,
            chatMemories: reconciledContext.chatMemories,
            personaID: persona.id,
            personaObservationChanges: validObservationChanges,
            learningMessageIDs: learningMessageIDs,
            historySummary: historySummary,
            summarizedMessageCount: olderMessages.count,
            summarizedPrefixFingerprint: messageFingerprint(olderMessages),
            replies: generated.replies,
            conversationStrategy: generated.conversationStrategy,
            strategyRationale: generated.strategyRationale,
            inputFingerprint: persistedFingerprint,
            promptVersion: SuggestedReplyPrompt.version
        )

        return SuggestedRepliesOutcome(
            replies: generated.replies,
            conversationStrategy: generated.conversationStrategy,
            strategyRationale: generated.strategyRationale,
            source: .generated
        )
    }

    private struct SummaryPlan {
        let mode: SuggestedReplySummaryMode
        let existingSummary: String
        let messages: [ChatMessageRecord]
    }

    private func makeSummaryPlan(
        olderMessages: [ChatMessageRecord],
        cache: SuggestedReplyCacheRecord?
    ) -> SummaryPlan {
        guard !olderMessages.isEmpty else {
            if let cache, cache.summarizedMessageCount == 0,
                cache.promptVersion == SuggestedReplyPrompt.version
            {
                return SummaryPlan(mode: .unchanged, existingSummary: "", messages: [])
            }
            return SummaryPlan(mode: .rebuild, existingSummary: "", messages: [])
        }

        guard let cache,
            cache.promptVersion == SuggestedReplyPrompt.version,
            cache.summarizedMessageCount <= olderMessages.count
        else {
            return SummaryPlan(mode: .rebuild, existingSummary: "", messages: olderMessages)
        }

        let cachedPrefix = Array(olderMessages.prefix(cache.summarizedMessageCount))
        guard messageFingerprint(cachedPrefix) == cache.summarizedPrefixFingerprint else {
            return SummaryPlan(mode: .rebuild, existingSummary: "", messages: olderMessages)
        }

        let newMessages = Array(olderMessages.dropFirst(cache.summarizedMessageCount))
        if newMessages.isEmpty {
            return SummaryPlan(
                mode: .unchanged, existingSummary: cache.historySummary, messages: [])
        }
        return SummaryPlan(
            mode: .incremental, existingSummary: cache.historySummary, messages: newMessages)
    }

    private func promptMessage(_ message: ChatMessageRecord) -> SuggestedReplyPromptMessage {
        SuggestedReplyPromptMessage(
            id: message.id,
            sender: message.senderKind,
            senderName: message.senderName,
            text: message.text,
            timeLabel: message.timeLabel
        )
    }

    private func fingerprint(
        messages: [ChatMessageRecord],
        chatContext: ChatContext,
        persona: PersonaPromptContext,
        learningMessageIDs: [UUID],
        provider: ProviderPlatform,
        model: ProviderModel
    ) -> String {
        let payload: [String: Any] = [
            "messages": messages.map(messageObject),
            "chatMemories": chatContext.chatMemories
                .filter { $0.status == .active }
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map(memoryObject),
            "currentInteractionGoal": chatContext.currentInteractionGoal,
            "persona": personaObject(persona),
            "personaLearningMessageIDs": learningMessageIDs.map(\.uuidString),
            "provider": provider.rawValue,
            "model": model.rawValue,
            "promptVersion": SuggestedReplyPrompt.version
        ]
        return digest(payload)
    }

    private func inputIsCurrent(
        chatID: String,
        expectedFingerprint: String,
        providerContext: AIProviderExecutionContext
    ) throws -> Bool {
        guard let currentContext = try? aiService.activeContext(requiring: .suggestedReplies),
            currentContext == providerContext,
            try repository.chat(id: chatID) != nil
        else {
            return false
        }
        let messages = try repository.messages(chatID: chatID)
        let context = try repository.chatContextValue(chatID: chatID)
        let persona = try repository.personaPromptContext(personaID: context.personaID)
        let learningMessages = try repository.personaLearningMessages(
            chatID: chatID, personaID: persona.id, assignedAt: context.personaAssignedAt
        )
        return fingerprint(
            messages: messages,
            chatContext: context,
            persona: persona,
            learningMessageIDs: learningMessages.map(\.id),
            provider: providerContext.platform,
            model: providerContext.effectiveModel
        ) == expectedFingerprint
    }

    private func messageFingerprint(_ messages: [ChatMessageRecord]) -> String {
        digest(messages.map(messageObject))
    }

    private func messageObject(_ message: ChatMessageRecord) -> [String: Any] {
        [
            "id": message.id.uuidString,
            "sender": message.senderKind,
            "senderName": message.senderName ?? NSNull(),
            "text": message.text,
            "timeLabel": message.timeLabel,
            "sortIndex": message.sortIndex
        ]
    }

    private func memoryObject(_ memory: ChatMemory) -> [String: Any] {
        [
            "id": memory.id.uuidString.lowercased(),
            "text": memory.text
        ]
    }

    private func personaObject(_ persona: PersonaPromptContext) -> [String: Any] {
        [
            "instructions": persona.instructions,
            "observations": persona.observations.map {
                [
                    "id": $0.id.uuidString, "text": $0.text,
                    "protected": $0.isUserProtected
                ] as [String: Any]
            }
        ]
    }

    private func digest(_ value: Any) -> String {
        let data =
            (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

}
