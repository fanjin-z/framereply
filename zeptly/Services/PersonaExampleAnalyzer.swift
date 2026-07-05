import Foundation

@MainActor
final class PersonaExampleAnalyzer {
    private let aiService: any AIServiceProviding
    private let repository: ChatRepository

    init(providerStore: any ProviderConfigurationProviding) {
        aiService = AIService(providerConfiguration: providerStore)
        repository = ChatRepository()
    }

    func analyze(personaID: UUID, examples: [String]) async throws {
        let provider = try aiService.activeContext(requiring: .suggestedReplies)
        let persona = try repository.personaPromptContext(personaID: personaID)
        let messages = examples.map {
            SuggestedReplyPromptMessage(
                id: UUID(), sender: "user", senderName: nil, text: $0, timeLabel: ""
            )
        }
        let request = SuggestedReplyGenerationRequest(
            chatName: "Writing samples",
            relationshipSubtitle: "",
            contactMemories: [],
            currentInteractionGoal: "Analyze the supplied writing examples. Replies are incidental.",
            persona: persona,
            personaLearningMessages: messages,
            existingHistorySummary: "",
            summaryMode: .unchanged,
            olderMessagesToSummarize: [],
            recentMessages: messages,
            traceID: ImportTraceID()
        )
        let result = try await aiService.generateSuggestedReplies(request, using: provider)
        try Task.checkCancellation()
        try repository.savePersonaExampleAnalysis(
            personaID: personaID,
            changes: result.personaTraitChanges,
            sampleMessageIDs: Set(messages.map(\.id)),
            sampleCount: examples.count
        )
    }
}
