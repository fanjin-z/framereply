import CryptoKit
import Foundation

nonisolated enum SuggestedReplyGenerationSource: String, Codable, Equatable, Sendable {
    case generated
    case cached
}

nonisolated struct SuggestedRepliesOutcome: Equatable, Sendable {
    let replies: [String]
    let source: SuggestedReplyGenerationSource
}

nonisolated enum SuggestedRepliesError: LocalizedError, Sendable {
    case noActiveProvider
    case missingAPIKey
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
        case .noMessages: "no_messages"
        case .chatNotFound: "chat_not_found"
        case .unsupportedProvider: "unsupported_provider"
        case .invalidProviderResponse: "reply_schema_mismatch"
        }
    }
}

@MainActor
final class SuggestedRepliesCoordinator {
    typealias ClientResolver = (ProviderPlatform) -> (any SuggestedReplyGenerating)?

    static let recentMessageLimit = 20

    private let providerStore: any ProviderConfigurationProviding
    private let repository: ChatRepository
    private let clientResolver: ClientResolver

    convenience init() {
        self.init(providerStore: ProviderStore())
    }

    convenience init(providerStore: any ProviderConfigurationProviding) {
        self.init(
            providerStore: providerStore,
            repository: ChatRepository(),
            clientResolver: Self.defaultClient(for:)
        )
    }

    init(
        providerStore: any ProviderConfigurationProviding,
        repository: ChatRepository,
        clientResolver: @escaping ClientResolver
    ) {
        self.providerStore = providerStore
        self.repository = repository
        self.clientResolver = clientResolver
    }

    func generate(
        chatID: String,
        force: Bool = false,
        traceID: ImportTraceID = ImportTraceID()
    ) async throws -> SuggestedRepliesOutcome {
        guard let activeProvider = providerStore.activeProvider else {
            throw SuggestedRepliesError.noActiveProvider
        }
        guard let apiKey = providerStore.savedAPIKey(for: activeProvider.platform), !apiKey.isEmpty else {
            throw SuggestedRepliesError.missingAPIKey
        }
        guard let client = clientResolver(activeProvider.platform) else {
            throw SuggestedRepliesError.unsupportedProvider
        }
        guard let chat = try repository.chat(id: chatID) else {
            throw SuggestedRepliesError.chatNotFound
        }

        let messages = try repository.messages(chatID: chatID)
        guard !messages.isEmpty else {
            throw SuggestedRepliesError.noMessages
        }

        let contactContext = try repository.contactContext(chatID: chatID)?.value ?? .empty
        let cache = try repository.suggestedReplyCache(chatID: chatID)
        let replyModel = activeProvider.model.suggestedReplyModel
        let inputFingerprint = fingerprint(
            chatName: chat.name,
            messages: messages,
            contactContext: contactContext,
            provider: activeProvider.platform,
            model: replyModel
        )

        if !force,
            let cache,
            cache.inputFingerprint == inputFingerprint,
            cache.promptVersion == SuggestedReplyPrompt.version,
            cache.replies.count == 2
        {
            return SuggestedRepliesOutcome(
                replies: cache.replies,
                source: .cached
            )
        }

        let olderCount = max(0, messages.count - Self.recentMessageLimit)
        let olderMessages = Array(messages.prefix(olderCount))
        let recentMessages = Array(messages.suffix(Self.recentMessageLimit))
        let summaryPlan = makeSummaryPlan(olderMessages: olderMessages, cache: cache)
        let request = SuggestedReplyGenerationRequest(
            chatName: chat.name,
            relationshipSubtitle: contactContext.relationshipSubtitle,
            relationshipNotes: contactContext.relationshipNotes,
            keyFacts: contactContext.keyFacts,
            currentInteractionGoal: contactContext.currentInteractionGoal,
            preferredPersona: contactContext.preferredPersona,
            existingHistorySummary: summaryPlan.existingSummary,
            summaryMode: summaryPlan.mode,
            olderMessagesToSummarize: summaryPlan.messages.map(promptMessage),
            recentMessages: recentMessages.map(promptMessage),
            traceID: traceID
        )

        let generated: SuggestedReplyGenerationResult
        do {
            generated = try await client.generateSuggestedReplies(
                request,
                apiKey: apiKey,
                model: replyModel
            )
        } catch let error as ProviderConnectionError {
            if case .structuredOutput = error {
                throw SuggestedRepliesError.invalidProviderResponse
            }
            throw error
        }
        try Task.checkCancellation()
        guard try inputIsCurrent(
            chatID: chatID,
            expectedFingerprint: inputFingerprint,
            provider: activeProvider.platform,
            model: replyModel
        ) else {
            throw CancellationError()
        }

        let historySummary: String
        switch summaryPlan.mode {
        case .unchanged:
            historySummary = summaryPlan.existingSummary
        case .incremental, .rebuild:
            historySummary = olderMessages.isEmpty ? "" : generated.historySummary
        }

        try repository.saveSuggestedReplyCache(
            chatID: chatID,
            historySummary: historySummary,
            summarizedMessageCount: olderMessages.count,
            summarizedPrefixFingerprint: messageFingerprint(olderMessages),
            replies: generated.replies,
            inputFingerprint: inputFingerprint,
            provider: activeProvider.platform,
            model: replyModel,
            promptVersion: SuggestedReplyPrompt.version
        )

        return SuggestedRepliesOutcome(
            replies: generated.replies,
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
            if let cache, cache.summarizedMessageCount == 0, cache.promptVersion == SuggestedReplyPrompt.version {
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
            return SummaryPlan(mode: .unchanged, existingSummary: cache.historySummary, messages: [])
        }
        return SummaryPlan(mode: .incremental, existingSummary: cache.historySummary, messages: newMessages)
    }

    private func promptMessage(_ message: ChatMessageRecord) -> SuggestedReplyPromptMessage {
        SuggestedReplyPromptMessage(
            sender: message.senderKind,
            senderName: message.senderName,
            text: message.text,
            timeLabel: message.timeLabel
        )
    }

    private func fingerprint(
        chatName: String,
        messages: [ChatMessageRecord],
        contactContext: ContactContext,
        provider: ProviderPlatform,
        model: ProviderModel
    ) -> String {
        let payload: [String: Any] = [
            "chatName": chatName,
            "messages": messages.map(messageObject),
            "relationshipSubtitle": contactContext.relationshipSubtitle,
            "relationshipNotes": contactContext.relationshipNotes,
            "keyFacts": contactContext.keyFacts,
            "currentInteractionGoal": contactContext.currentInteractionGoal,
            "preferredPersona": contactContext.preferredPersona,
            "provider": provider.rawValue,
            "model": model.rawValue,
            "promptVersion": SuggestedReplyPrompt.version
        ]
        return digest(payload)
    }

    private func inputIsCurrent(
        chatID: String,
        expectedFingerprint: String,
        provider: ProviderPlatform,
        model: ProviderModel
    ) throws -> Bool {
        guard let activeProvider = providerStore.activeProvider,
            activeProvider.platform == provider,
            activeProvider.model.suggestedReplyModel == model,
            let chat = try repository.chat(id: chatID)
        else {
            return false
        }
        let messages = try repository.messages(chatID: chatID)
        let context = try repository.contactContext(chatID: chatID)?.value ?? .empty
        return fingerprint(
            chatName: chat.name,
            messages: messages,
            contactContext: context,
            provider: provider,
            model: model
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

    private func digest(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultClient(for platform: ProviderPlatform) -> (any SuggestedReplyGenerating)? {
        switch platform {
        case .openAI:
            OpenAIClient()
        case .zaiInternational:
            ZAIClient(region: .international)
        case .zhipuChina:
            ZAIClient(region: .china)
        }
    }
}
