import Foundation
import XCTest

@testable import FrameReply

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
            platform: .openAI,
            selectedTier: .advanced,
            apiKey: "validation-key"
        )
        XCTAssertEqual(adapter.validatedModels, [.gpt6Luna])

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
        XCTAssertEqual(replyContext.effectiveModel, .gpt6Sol)
        let result = try await service.generateSuggestedReplies(
            makeReplyRequest(),
            using: replyContext
        )

        XCTAssertEqual(result.replies, ["First", "Second"])
        XCTAssertEqual(adapter.analysisModels, [.gpt6Luna, .gpt56Terra])
        XCTAssertEqual(adapter.replyModels, [.gpt6Sol])
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
        let adapter = RecordingProviderAdapter(platform: .frameReplyAI)
        let configuration = GatewayProviderConfiguration(
            platform: .frameReplyAI, managedModel: .managedGPT6Luna)
        let service = AIService(
            providerConfiguration: configuration,
            registry: AIProviderRegistry(adapters: [adapter]))

        let context = try await service.prepareContext(requiring: .suggestedReplies)
        XCTAssertEqual(context.platform, .frameReplyAI)
        XCTAssertEqual(context.effectiveModel, .managedGPT6Luna)
        _ = try await service.generateSuggestedReplies(makeReplyRequest(), using: context)

        XCTAssertEqual(adapter.replyModels, [.managedGPT6Luna])
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
        managedModel: ProviderModel? = nil
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
    private(set) var validatedModels: [ProviderModel] = []
    private(set) var analysisModels: [ProviderModel] = []
    private(set) var replyModels: [ProviderModel] = []
    private(set) var apiKeys: [String] = []

    init(platform: ProviderPlatform = .openAI) {
        self.platform = platform
    }

    func modelProfile(for selectedTier: ProviderTier) -> ProviderModelProfile? {
        guard selectedTier == (platform == .frameReplyAI ? .basic : .advanced) else {
            return nil
        }
        return ProviderModelProfile(
            screenshotAnalysisModel: .gpt6Luna,
            transcriptAnalysisModel: .gpt56Terra,
            suggestedReplyModel: .gpt6Sol
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
