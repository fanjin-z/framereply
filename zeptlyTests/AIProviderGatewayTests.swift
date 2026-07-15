import Foundation
import XCTest

@testable import zeptly

final class AIProviderGatewayTests: XCTestCase {
    @MainActor
    func testGatewayResolvesCredentialsAndRoutesTaskSpecificModels() async throws {
        let adapter = RecordingProviderAdapter()
        let configuration = GatewayProviderConfiguration()
        let service = AIService(
            providerConfiguration: configuration,
            registry: AIProviderRegistry(adapters: [adapter])
        )

        try await service.validate(
            platform: .zaiInternational,
            selectedTier: .advanced,
            apiKey: "validation-key"
        )
        XCTAssertEqual(adapter.validatedModels, [.glm46VFlashX])

        let analysisContext = try service.activeContext(requiring: .screenshotAnalysis)
        XCTAssertEqual(analysisContext.effectiveModel, .glm46VFlashX)
        _ = try await service.analyzeChatScreenshot(
            ChatScreenshotAnalysisRequest(imageData: Data([1]), candidates: []),
            using: analysisContext
        )

        let transcriptContext = try service.activeContext(requiring: .transcriptAnalysis)
        XCTAssertEqual(transcriptContext.effectiveModel, .glm47FlashX)
        _ = try await service.analyzeChatScreenshot(
            ChatScreenshotAnalysisRequest(transcriptItems: ["Alex: Hello"], candidates: []),
            using: transcriptContext
        )

        let replyContext = try service.activeContext(requiring: .suggestedReplies)
        XCTAssertEqual(replyContext.effectiveModel, .glm47FlashX)
        let result = try await service.generateSuggestedReplies(
            makeReplyRequest(),
            using: replyContext
        )

        XCTAssertEqual(result.replies, ["First", "Second"])
        XCTAssertEqual(adapter.analysisModels, [.glm46VFlashX, .glm47FlashX])
        XCTAssertEqual(adapter.replyModels, [.glm47FlashX])
        XCTAssertEqual(
            adapter.apiKeys, ["validation-key", "saved-key", "saved-key", "saved-key"])
    }

    @MainActor
    func testRevokedConsentStopsBeforeAnyProviderRequest() async throws {
        let adapter = RecordingProviderAdapter()
        let configuration = GatewayProviderConfiguration(hasConsent: false)
        let service = AIService(
            providerConfiguration: configuration,
            registry: AIProviderRegistry(adapters: [adapter])
        )

        XCTAssertThrowsError(try service.activeContext(requiring: .screenshotAnalysis)) { error in
            XCTAssertEqual(error as? AIServiceError, .consentRequired)
        }
        XCTAssertTrue(adapter.apiKeys.isEmpty)
        XCTAssertTrue(adapter.analysisModels.isEmpty)
    }

    private func makeReplyRequest() -> SuggestedReplyGenerationRequest {
        SuggestedReplyGenerationRequest(
            task: .standard,
            chatMemories: [],
            currentInteractionGoal: "Reply",
            persona: PersonaPromptContext(
                id: UUID(), name: "Warm",
                instructions: "Write warmly.", observations: [], protectedTombstones: []
            ),
            personaLearningMessages: [],
            existingHistorySummary: "",
            summaryMode: .unchanged,
            olderMessagesToSummarize: [],
            recentMessages: [],
            traceID: ImportTraceID()
        )
    }
}

@MainActor
private final class GatewayProviderConfiguration: ProviderConfigurationProviding {
    let activeProvider: ProviderConnection? = ProviderConnection(
        platform: .zaiInternational,
        tier: .advanced
    )
    private let hasConsent: Bool

    init(hasConsent: Bool = true) {
        self.hasConsent = hasConsent
    }

    func savedAPIKey(for platform: ProviderPlatform) -> String? {
        "saved-key"
    }

    func hasValidDataConsent(for platform: ProviderPlatform) -> Bool {
        hasConsent
    }
}

private final class RecordingProviderAdapter: @MainActor AIProviderAdapter {
    let platform = ProviderPlatform.zaiInternational
    private(set) var validatedModels: [ProviderModel] = []
    private(set) var analysisModels: [ProviderModel] = []
    private(set) var replyModels: [ProviderModel] = []
    private(set) var apiKeys: [String] = []

    func modelProfile(for selectedTier: ProviderTier) -> ProviderModelProfile? {
        guard selectedTier == .advanced else { return nil }
        return ProviderModelProfile(
            screenshotAnalysisModel: .glm46VFlashX,
            transcriptAnalysisModel: .glm47FlashX,
            suggestedReplyModel: .glm47FlashX
        )
    }

    func validate(apiKey: String, model: ProviderModel) async throws {
        validatedModels.append(model)
        apiKeys.append(apiKey)
    }

    func analyzeChatScreenshot(
        _ request: ChatScreenshotAnalysisRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> ChatImportAnalysis {
        analysisModels.append(model)
        apiKeys.append(apiKey)
        return ChatImportAnalysis(
            conversationTitle: nil,
            messages: [],
            matchedChatID: nil,
            matchConfidence: 0
        )
    }

    func generateSuggestedReplies(
        _ request: SuggestedReplyGenerationRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> SuggestedReplyGenerationResult {
        replyModels.append(model)
        apiKeys.append(apiKey)
        return SuggestedReplyGenerationResult(
            historySummary: "",
            replies: ["First", "Second"],
            conversationStrategy: "Reply directly.",
            strategyRationale: "The gateway test only verifies routing."
        )
    }
}
