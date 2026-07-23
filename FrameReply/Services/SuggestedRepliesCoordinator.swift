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
            String(localized: AppStrings.Errors.Replies.noProvider)
        case .missingAPIKey:
            String(localized: AppStrings.Errors.AI.missingKey)
        case .consentRequired:
            String(localized: AppStrings.Errors.Replies.consentRequired)
        case .noMessages:
            String(localized: AppStrings.Errors.Replies.noMessages)
        case .chatNotFound:
            String(localized: AppStrings.Errors.Replies.chatNotFound)
        case .unsupportedProvider:
            String(localized: AppStrings.Errors.Replies.unsupportedProvider)
        case .invalidProviderResponse:
            String(localized: AppStrings.Errors.Replies.invalidResponse)
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

    func cachedReplies(
        chatID: String,
        localization: LocalizationContext = .current
    ) throws -> SuggestedRepliesOutcome? {
        guard let providerContext = try? aiService.activeContext(requiring: .suggestedReplies),
            try repository.chat(id: chatID) != nil
        else {
            return nil
        }
        let messages = try repository.messages(chatID: chatID)
        guard !messages.isEmpty else { return nil }
        let provisionalIdentity = try repository.provisionalIdentityInterpretation(chatID: chatID)

        let chatContext = try repository.chatContextValue(chatID: chatID)
        let persona = try repository.personaPromptContext(personaID: chatContext.personaID)
        let learningMessages = try repository.personaLearningMessages(
            chatID: chatID,
            personaID: persona.id,
            assignedAt: chatContext.personaAssignedAt
        )
        guard
            let cache = try repository.suggestedReplyCache(
                chatID: chatID,
                presentationLanguageIdentifier: localization.languageIdentifier
            )
        else {
            return nil
        }
        let inputFingerprint = fingerprint(
            messages: messages,
            chatContext: chatContext,
            persona: persona,
            learningMessageIDs: learningMessages.map(\.id),
            provider: providerContext.platform,
            model: providerContext.effectiveModel,
            presentationLanguageIdentifier: localization.languageIdentifier,
            provisionalIdentity: provisionalIdentity
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
        localization: LocalizationContext = .current,
        traceID: ImportTraceID = ImportTraceID()
    ) async throws -> SuggestedRepliesOutcome {
        let oneUseInput = try DraftingInputLimits.validated(draftingInput)
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
        let provisionalIdentity = try repository.provisionalIdentityInterpretation(chatID: chatID)

        let chatContext = try repository.chatContextValue(chatID: chatID)
        let persona = try repository.personaPromptContext(personaID: chatContext.personaID)
        let learningMessages = try repository.personaLearningMessages(
            chatID: chatID,
            personaID: persona.id,
            assignedAt: chatContext.personaAssignedAt
        )
        let cache = try repository.suggestedReplyCache(
            chatID: chatID,
            presentationLanguageIdentifier: localization.languageIdentifier
        )
        let replyModel = providerContext.effectiveModel
        let inputFingerprint = fingerprint(
            messages: messages,
            chatContext: chatContext,
            persona: persona,
            learningMessageIDs: learningMessages.map(\.id),
            provider: providerContext.platform,
            model: replyModel,
            presentationLanguageIdentifier: localization.languageIdentifier,
            provisionalIdentity: provisionalIdentity
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
        let summaryPlan = makeSummaryPlan(
            olderMessages: olderMessages,
            cache: provisionalIdentity == nil ? cache : nil
        )
        let previousConversationStrategy =
            provisionalIdentity == nil
            ? cache?.conversationStrategy
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let strategyContext = previousConversationStrategy.flatMap { $0.isEmpty ? nil : $0 }
        let request = SuggestedReplyGenerationRequest(
            task: oneUseInput == nil ? .standard : .drafting,
            chatMemories: chatContext.chatMemories.filter { $0.status == .active },
            currentInteractionGoal: chatContext.currentInteractionGoal,
            persona: persona,
            personaLearningMessages: learningMessages.map {
                promptMessage($0, provisionalIdentity: provisionalIdentity)
            },
            existingHistorySummary: summaryPlan.existingSummary,
            olderMessagesToSummarize: summaryPlan.messages.map {
                promptMessage($0, provisionalIdentity: provisionalIdentity)
            },
            recentMessages: recentMessages.map {
                promptMessage($0, provisionalIdentity: provisionalIdentity)
            },
            draftingInput: oneUseInput,
            previousConversationStrategy: strategyContext,
            presentationLanguageIdentifier: localization.languageIdentifier,
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
                providerContext: providerContext,
                presentationLanguageIdentifier: localization.languageIdentifier
            )
        else {
            throw CancellationError()
        }

        let historySummary: String
        let summarizedMessageCount: Int
        let summarizedPrefixFingerprint: String
        if !summaryPlan.messages.isEmpty, let updatedSummary = generated.historySummary {
            historySummary = updatedSummary
            summarizedMessageCount = olderMessages.count
            summarizedPrefixFingerprint = messageFingerprint(olderMessages)
        } else {
            historySummary = summaryPlan.existingSummary
            summarizedMessageCount = summaryPlan.summarizedMessageCount
            summarizedPrefixFingerprint = summaryPlan.summarizedPrefixFingerprint
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
        let learningMessageIDList = learningMessages.map(\.id)
        let learningMessageIDs = Set(learningMessageIDList)
        let validObservationChanges = generated.personaObservationChanges.filter {
            $0.sourceMessageIDs.count >= 2
                && $0.sourceMessageIDs.allSatisfy(learningMessageIDs.contains)
        }
        let processedLearningMessageIDs =
            generated.personaObservationChangesAvailable ? learningMessageIDs : []
        let remainingLearningMessageIDs =
            generated.personaObservationChangesAvailable ? [] : learningMessageIDList

        // Input-specific and provisionally grounded output cannot affect
        // summaries, memory, or persona learning. Cache only its replies so the
        // app can show the same result.
        if oneUseInput != nil || provisionalIdentity != nil {
            try repository.saveSuggestedRepliesOnly(
                chatID: chatID,
                presentationLanguageIdentifier: localization.languageIdentifier,
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
            learningMessageIDs: remainingLearningMessageIDs,
            provider: providerContext.platform,
            model: replyModel,
            presentationLanguageIdentifier: localization.languageIdentifier,
            provisionalIdentity: nil
        )

        try repository.saveSuggestedReplyGeneration(
            chatID: chatID,
            presentationLanguageIdentifier: localization.languageIdentifier,
            chatMemories: reconciledContext.chatMemories,
            personaID: persona.id,
            personaObservationChanges: validObservationChanges,
            learningMessageIDs: processedLearningMessageIDs,
            historySummary: historySummary,
            summarizedMessageCount: summarizedMessageCount,
            summarizedPrefixFingerprint: summarizedPrefixFingerprint,
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
        let existingSummary: String
        let summarizedMessageCount: Int
        let summarizedPrefixFingerprint: String
        let messages: [ChatMessageRecord]
    }

    private func makeSummaryPlan(
        olderMessages: [ChatMessageRecord],
        cache: SuggestedReplyCacheRecord?
    ) -> SummaryPlan {
        let emptyPrefixFingerprint = messageFingerprint([])
        guard !olderMessages.isEmpty else {
            return SummaryPlan(
                existingSummary: "",
                summarizedMessageCount: 0,
                summarizedPrefixFingerprint: emptyPrefixFingerprint,
                messages: []
            )
        }

        guard let cache,
            cache.promptVersion == SuggestedReplyPrompt.version,
            cache.summarizedMessageCount <= olderMessages.count,
            (cache.summarizedMessageCount == 0
                && cache.historySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                || (cache.summarizedMessageCount > 0
                    && !cache.historySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        else {
            return SummaryPlan(
                existingSummary: "",
                summarizedMessageCount: 0,
                summarizedPrefixFingerprint: emptyPrefixFingerprint,
                messages: olderMessages
            )
        }

        let cachedPrefix = Array(olderMessages.prefix(cache.summarizedMessageCount))
        guard messageFingerprint(cachedPrefix) == cache.summarizedPrefixFingerprint else {
            return SummaryPlan(
                existingSummary: "",
                summarizedMessageCount: 0,
                summarizedPrefixFingerprint: emptyPrefixFingerprint,
                messages: olderMessages
            )
        }

        let newMessages = Array(olderMessages.dropFirst(cache.summarizedMessageCount))
        return SummaryPlan(
            existingSummary: cache.historySummary,
            summarizedMessageCount: cache.summarizedMessageCount,
            summarizedPrefixFingerprint: cache.summarizedPrefixFingerprint,
            messages: newMessages
        )
    }

    private func promptMessage(
        _ message: ChatMessageRecord,
        provisionalIdentity: ProvisionalIdentityInterpretation?
    ) -> SuggestedReplyPromptMessage {
        let senderName: String?
        if let provisionalIdentity {
            senderName = provisionalIdentity.senderName(for: message)
        } else {
            senderName = message.senderName
        }
        return SuggestedReplyPromptMessage(
            id: message.id,
            sender: provisionalIdentity?.senderKind(for: message) ?? message.senderKind,
            senderName: senderName,
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
        model: ProviderModel,
        presentationLanguageIdentifier: String,
        provisionalIdentity: ProvisionalIdentityInterpretation?
    ) -> String {
        let payload: [String: Any] = [
            "messages": messages.map {
                messageObject($0, provisionalIdentity: provisionalIdentity)
            },
            "chatMemories": chatContext.chatMemories
                .filter { $0.status == .active }
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map(memoryObject),
            "currentInteractionGoal": chatContext.currentInteractionGoal,
            "persona": personaObject(persona),
            "personaLearningMessageIDs": learningMessageIDs.map(\.uuidString),
            "provider": provider.rawValue,
            "model": model.rawValue,
            "presentationLanguageIdentifier": presentationLanguageIdentifier,
            "provisionalIdentity": provisionalIdentity.map(identityObject) ?? NSNull(),
            "promptVersion": SuggestedReplyPrompt.version
        ]
        return digest(payload)
    }

    private func inputIsCurrent(
        chatID: String,
        expectedFingerprint: String,
        providerContext: AIProviderExecutionContext,
        presentationLanguageIdentifier: String
    ) throws -> Bool {
        guard let currentContext = try? aiService.activeContext(requiring: .suggestedReplies),
            currentContext == providerContext,
            try repository.chat(id: chatID) != nil
        else {
            return false
        }
        let messages = try repository.messages(chatID: chatID)
        let provisionalIdentity = try repository.provisionalIdentityInterpretation(chatID: chatID)
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
            model: providerContext.effectiveModel,
            presentationLanguageIdentifier: presentationLanguageIdentifier,
            provisionalIdentity: provisionalIdentity
        ) == expectedFingerprint
    }

    private func messageFingerprint(_ messages: [ChatMessageRecord]) -> String {
        digest(messages.map { messageObject($0, provisionalIdentity: nil) })
    }

    private func messageObject(
        _ message: ChatMessageRecord,
        provisionalIdentity: ProvisionalIdentityInterpretation?
    ) -> [String: Any] {
        let senderName: String?
        if let provisionalIdentity {
            senderName = provisionalIdentity.senderName(for: message)
        } else {
            senderName = message.senderName
        }
        let sender = provisionalIdentity?.senderKind(for: message) ?? message.senderKind
        return [
            "id": message.id.uuidString,
            "sender": sender,
            "senderName": senderName ?? NSNull(),
            "text": message.text,
            "timeLabel": message.timeLabel,
            "sortIndex": message.sortIndex
        ]
    }

    private func identityObject(
        _ identity: ProvisionalIdentityInterpretation
    ) -> [String: Any] {
        [
            "selfDisplayLabel": identity.selfDisplayLabel,
            "counterpartDisplayLabel": identity.counterpartDisplayLabel,
            "displayTitle": identity.displayTitle
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
