import Foundation
import XCTest

@testable import FrameReply

final class AIProviderGatewayTests: XCTestCase {
    @MainActor
    func testGatewayResolvesCredentialsAndRoutesTaskSpecificModels() async throws {
        // A different Basic model catches probes that hardcode the current catalog model.
        let adapter = RecordingProviderAdapter(basicModel: .gpt56Terra)
        let configuration = GatewayProviderConfiguration()
        let service = AIService(
            providerConfiguration: configuration,
            registry: AIProviderRegistry(adapters: [adapter])
        )

        try await service.validate(
            platform: .openAI,
            apiKey: "validation-key"
        )
        XCTAssertEqual(adapter.validatedModels, [.gpt56Terra])

        let analysisContext = try service.activeContext(requiring: .screenshotAnalysis)
        XCTAssertEqual(analysisContext.effectiveModel, .gpt6Luna)
        _ = try await service.analyzeChatScreenshot(
            ChatScreenshotAnalysisRequest(imageData: Data([1]), candidates: []),
            using: analysisContext
        )

        let transcriptContext = try service.activeContext(requiring: .transcriptAnalysis)
        XCTAssertEqual(transcriptContext.effectiveModel, .gpt56Terra)
        _ = try await service.analyzeChatScreenshot(
            ChatScreenshotAnalysisRequest(transcriptItems: ["Alex: Hello"], candidates: []),
            using: transcriptContext
        )

        let replyContext = try service.activeContext(requiring: .suggestedReplies)
        XCTAssertEqual(replyContext.effectiveModel, .gpt61Sol)
        let result = try await service.generateSuggestedReplies(
            makeReplyRequest(),
            using: replyContext
        )

        XCTAssertEqual(result.replies, ["First", "Second"])
        XCTAssertEqual(adapter.analysisModels, [.gpt6Luna, .gpt56Terra])
        XCTAssertEqual(adapter.replyModels, [.gpt61Sol])
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

    @MainActor
    func testManagedConnectionUsesBackendModelAndCappedKey() async throws {
        let usageInvalidated = expectation(
            forNotification: AIAccessModel.usageDidChange, object: nil)
        let adapter = RecordingProviderAdapter(platform: .frameReplyAI)
        let modelID = try XCTUnwrap(ManagedOpenRouterModelID(rawValue: "openai/future-model"))
        let model = ManagedOpenRouterModel(requestID: modelID, responseID: modelID)
        let configuration = GatewayProviderConfiguration(
            platform: .frameReplyAI, managedModel: model)
        let service = AIService(
            providerConfiguration: configuration,
            registry: AIProviderRegistry(adapters: [adapter]))

        let context = try await service.prepareContext(requiring: .suggestedReplies)
        XCTAssertEqual(context.platform, .frameReplyAI)
        XCTAssertEqual(context.effectiveModel, .managedOpenRouter(model))
        _ = try await service.generateSuggestedReplies(makeReplyRequest(), using: context)
        await fulfillment(of: [usageInvalidated], timeout: 1)

        XCTAssertEqual(adapter.replyModels, [.managedOpenRouter(model)])
        XCTAssertEqual(adapter.apiKeys, ["saved-key"])
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
            existingHistorySummary: "",
            olderMessagesToSummarize: [],
            recentMessages: [],
            appLanguage: "en",
            traceID: ImportTraceID()
        )
    }
}

@MainActor
private final class GatewayProviderConfiguration: ProviderConfigurationProviding {
    let activeProvider: ProviderConnection?
    private let hasConsent: Bool

    init(
        hasConsent: Bool = true, platform: ProviderPlatform = .openAI,
        managedModel: ManagedOpenRouterModel? = nil
    ) {
        self.hasConsent = hasConsent
        activeProvider = ProviderConnection(
            platform: platform,
            tier: platform == .frameReplyAI ? .basic : .advanced,
            managedModel: managedModel)
    }

    func savedAPIKey(for platform: ProviderPlatform) -> String? {
        "saved-key"
    }

    func hasValidDataConsent(for platform: ProviderPlatform) -> Bool {
        hasConsent
    }
}

private final class RecordingProviderAdapter: @MainActor AIProviderAdapter {
    let platform: ProviderPlatform
    private let basicModel: ProviderModel
    private(set) var validatedModels: [ProviderModel] = []
    private(set) var analysisModels: [ProviderModel] = []
    private(set) var replyModels: [ProviderModel] = []
    private(set) var apiKeys: [String] = []

    init(platform: ProviderPlatform = .openAI, basicModel: ProviderModel = .gpt6Luna) {
        self.platform = platform
        self.basicModel = basicModel
    }

    func modelProfile(for selectedTier: ProviderTier) -> ProviderModelProfile? {
        guard platform.supportedTiers.contains(selectedTier) else {
            return nil
        }
        if selectedTier == .basic {
            return ProviderModelProfile(
                screenshotAnalysisModel: basicModel,
                transcriptAnalysisModel: basicModel,
                suggestedReplyModel: basicModel
            )
        }
        return ProviderModelProfile(
            screenshotAnalysisModel: .gpt6Luna,
            transcriptAnalysisModel: .gpt56Terra,
            suggestedReplyModel: .gpt61Sol
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
