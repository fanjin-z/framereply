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
            selectedModel: .glm46VFlashX,
            apiKey: "validation-key"
        )
        XCTAssertEqual(adapter.validatedModels, [.glm46VFlashX])

        let analysisContext = try service.activeContext(requiring: .screenshotAnalysis)
        XCTAssertEqual(analysisContext.effectiveModel, .glm46VFlashX)
        _ = try await service.analyzeChatScreenshot(
            ChatScreenshotAnalysisRequest(imageData: Data([1]), candidates: []),
            using: analysisContext
        )

        let replyContext = try service.activeContext(requiring: .suggestedReplies)
        XCTAssertEqual(replyContext.effectiveModel, .glm47FlashX)
        let result = try await service.generateSuggestedReplies(
            makeReplyRequest(),
            using: replyContext
        )

        XCTAssertEqual(result.replies, ["First", "Second"])
        XCTAssertEqual(adapter.analysisModels, [.glm46VFlashX])
        XCTAssertEqual(adapter.replyModels, [.glm47FlashX])
        XCTAssertEqual(adapter.apiKeys, ["validation-key", "saved-key", "saved-key"])
    }

    @MainActor
    func testEveryLiveAdapterExposesEquivalentTypedCapabilities() throws {
        let registry = AIProviderRegistry.live()
        let selections: [(ProviderPlatform, ProviderModel, ProviderModel)] = [
            (.openAI, .gpt54Mini, .gpt54Mini),
            (.zaiInternational, .glm46VFlashX, .glm47FlashX),
            (.zhipuChina, .glm46VFlashX, .glm47FlashX)
        ]

        for (platform, selectedModel, replyModel) in selections {
            let profile = try XCTUnwrap(
                registry.profile(for: platform, selectedModel: selectedModel)
            )
            XCTAssertEqual(profile.capabilities, [.screenshotAnalysis, .suggestedReplies])
            XCTAssertEqual(profile.screenshotAnalysisModel, selectedModel)
            XCTAssertEqual(profile.suggestedReplyModel, replyModel)
        }
    }

    private func makeReplyRequest() -> SuggestedReplyGenerationRequest {
        SuggestedReplyGenerationRequest(
            chatName: "Sarah",
            relationshipSubtitle: "Friend",
            contactMemories: [],
            currentInteractionGoal: "Reply",
            persona: PersonaPromptContext(
                id: PersonaDefaults.professionalID, name: "Warm",
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
        model: .glm46VFlashX,
        lastValidatedAt: Date(),
        validationState: .connected
    )

    func savedAPIKey(for platform: ProviderPlatform) -> String? {
        "saved-key"
    }
}

@MainActor
private final class RecordingProviderAdapter: AIProviderAdapter {
    let platform = ProviderPlatform.zaiInternational
    private(set) var validatedModels: [ProviderModel] = []
    private(set) var analysisModels: [ProviderModel] = []
    private(set) var replyModels: [ProviderModel] = []
    private(set) var apiKeys: [String] = []

    func modelProfile(for selectedModel: ProviderModel) -> ProviderModelProfile? {
        guard selectedModel == .glm46VFlashX else { return nil }
        return ProviderModelProfile(
            selectedModel: selectedModel,
            screenshotAnalysisModel: .glm46VFlashX,
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
            replies: ["First", "Second"]
        )
    }
}
