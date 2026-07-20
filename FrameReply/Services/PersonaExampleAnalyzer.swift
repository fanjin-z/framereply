import Foundation

@MainActor
final class PersonaExampleAnalyzer {
    private let aiService: any AIServiceProviding
    private let repository: ChatRepository

    init(providerStore: any ProviderConfigurationProviding) {
        aiService = AIService(providerConfiguration: providerStore)
        repository = ChatRepository()
    }

    func analyze(
        personaID: UUID,
        examples: [String],
        localization: LocalizationContext = .current
    ) async throws {
        let persona = try repository.personaPromptContext(personaID: personaID)
        let analysis = try await analyze(
            persona: persona, examples: examples, localization: localization)
        try repository.savePersonaExampleAnalysis(
            personaID: personaID,
            changes: analysis.changes,
            sampleMessageIDs: analysis.messageIDs,
            sampleCount: examples.count
        )
    }

    func analyze(
        persona: PersonaPromptContext,
        examples: [String],
        localization: LocalizationContext = .current
    ) async throws -> (changes: [PersonaObservationChange], messageIDs: Set<UUID>) {
        let provider = try aiService.activeContext(requiring: .suggestedReplies)
        let messages = examples.map {
            SuggestedReplyPromptMessage(
                id: UUID(), sender: "user", senderName: nil, text: $0, timeLabel: ""
            )
        }
        let request = SuggestedReplyGenerationRequest(
            task: .personaStyleLearning,
            chatMemories: [],
            currentInteractionGoal:
                "Analyze the supplied writing examples. Replies are incidental.",
            persona: persona,
            personaLearningMessages: messages,
            existingHistorySummary: "",
            summaryMode: .unchanged,
            olderMessagesToSummarize: [],
            recentMessages: [],
            presentationLanguageIdentifier: localization.languageIdentifier,
            traceID: ImportTraceID()
        )
        let result = try await aiService.generateSuggestedReplies(request, using: provider)
        try Task.checkCancellation()
        return (result.personaObservationChanges, Set(messages.map(\.id)))
    }
}
