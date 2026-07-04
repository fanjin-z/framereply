import Foundation

nonisolated enum AIProviderCapability: String, CaseIterable, Hashable, Sendable {
    case screenshotAnalysis
    case suggestedReplies
}

nonisolated struct ProviderModelProfile: Equatable, Sendable {
    let selectedModel: ProviderModel
    let screenshotAnalysisModel: ProviderModel?
    let suggestedReplyModel: ProviderModel?

    var capabilities: Set<AIProviderCapability> {
        var result: Set<AIProviderCapability> = []
        if screenshotAnalysisModel != nil {
            result.insert(.screenshotAnalysis)
        }
        if suggestedReplyModel != nil {
            result.insert(.suggestedReplies)
        }
        return result
    }

    func model(for capability: AIProviderCapability) -> ProviderModel? {
        switch capability {
        case .screenshotAnalysis:
            screenshotAnalysisModel
        case .suggestedReplies:
            suggestedReplyModel
        }
    }
}

@MainActor
protocol AIProviderAdapter: ProviderValidator, ChatScreenshotAnalyzing, SuggestedReplyGenerating {
    var platform: ProviderPlatform { get }
    func modelProfile(for selectedModel: ProviderModel) -> ProviderModelProfile?
}

@MainActor
struct AIProviderRegistry {
    private let adapters: [ProviderPlatform: any AIProviderAdapter]

    init(adapters: [any AIProviderAdapter]) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.platform, $0) })
    }

    static func live(
        eventReporter: any ImportEventReporting = OSLogImportEventReporter()
    ) -> AIProviderRegistry {
        AIProviderRegistry(adapters: [
            OpenAIClient(eventReporter: eventReporter),
            ZAIClient(region: .international, eventReporter: eventReporter),
            ZAIClient(region: .china, eventReporter: eventReporter)
        ])
    }

    func adapter(for platform: ProviderPlatform) -> (any AIProviderAdapter)? {
        adapters[platform]
    }

    func profile(
        for platform: ProviderPlatform,
        selectedModel: ProviderModel
    ) -> ProviderModelProfile? {
        adapters[platform]?.modelProfile(for: selectedModel)
    }
}

nonisolated struct AIProviderExecutionContext: Equatable, Sendable {
    let platform: ProviderPlatform
    let profile: ProviderModelProfile
    let capability: AIProviderCapability
    let effectiveModel: ProviderModel
}

nonisolated enum AIServiceError: LocalizedError, Sendable {
    case noActiveProvider
    case missingAPIKey
    case unsupportedProvider
    case unsupportedCapability

    var errorDescription: String? {
        switch self {
        case .noActiveProvider:
            "Connect and select a model provider first."
        case .missingAPIKey:
            "The selected provider API key is unavailable. Reconnect it in Settings."
        case .unsupportedProvider:
            "The selected provider is not available."
        case .unsupportedCapability:
            "The selected provider does not support this AI task."
        }
    }

    var code: String {
        switch self {
        case .noActiveProvider: "no_provider"
        case .missingAPIKey: "missing_api_key"
        case .unsupportedProvider, .unsupportedCapability: "unsupported_provider"
        }
    }
}

@MainActor
protocol AIServiceProviding: AnyObject {
    func activeContext(
        requiring capability: AIProviderCapability
    ) throws -> AIProviderExecutionContext

    func analyzeChatScreenshot(
        _ request: ChatScreenshotAnalysisRequest,
        using context: AIProviderExecutionContext
    ) async throws -> ChatImportAnalysis

    func generateSuggestedReplies(
        _ request: SuggestedReplyGenerationRequest,
        using context: AIProviderExecutionContext
    ) async throws -> SuggestedReplyGenerationResult
}

@MainActor
final class AIService: AIServiceProviding {
    private let providerConfiguration: (any ProviderConfigurationProviding)?
    private let registry: AIProviderRegistry

    convenience init(
        providerConfiguration: (any ProviderConfigurationProviding)? = nil
    ) {
        self.init(providerConfiguration: providerConfiguration, registry: .live())
    }

    init(
        providerConfiguration: (any ProviderConfigurationProviding)? = nil,
        registry: AIProviderRegistry
    ) {
        self.providerConfiguration = providerConfiguration
        self.registry = registry
    }

    func validate(
        platform: ProviderPlatform,
        selectedModel: ProviderModel,
        apiKey: String
    ) async throws {
        guard let adapter = registry.adapter(for: platform) else {
            throw AIServiceError.unsupportedProvider
        }
        guard let profile = adapter.modelProfile(for: selectedModel),
            let validationModel = profile.screenshotAnalysisModel ?? profile.suggestedReplyModel
        else {
            throw AIServiceError.unsupportedCapability
        }
        try await adapter.validate(apiKey: apiKey, model: validationModel)
    }

    func activeContext(
        requiring capability: AIProviderCapability
    ) throws -> AIProviderExecutionContext {
        guard let providerConfiguration,
            let connection = providerConfiguration.activeProvider
        else {
            throw AIServiceError.noActiveProvider
        }
        guard let adapter = registry.adapter(for: connection.platform),
            let profile = adapter.modelProfile(for: connection.model)
        else {
            throw AIServiceError.unsupportedProvider
        }
        guard let effectiveModel = profile.model(for: capability) else {
            throw AIServiceError.unsupportedCapability
        }
        guard providerConfiguration.savedAPIKey(for: connection.platform)?.isEmpty == false
        else {
            throw AIServiceError.missingAPIKey
        }
        return AIProviderExecutionContext(
            platform: connection.platform,
            profile: profile,
            capability: capability,
            effectiveModel: effectiveModel
        )
    }

    func analyzeChatScreenshot(
        _ request: ChatScreenshotAnalysisRequest,
        using context: AIProviderExecutionContext
    ) async throws -> ChatImportAnalysis {
        guard context.capability == .screenshotAnalysis else {
            throw AIServiceError.unsupportedCapability
        }
        let (adapter, apiKey) = try resolve(context)
        return try await adapter.analyzeChatScreenshot(
            request,
            apiKey: apiKey,
            model: context.effectiveModel
        )
    }

    func generateSuggestedReplies(
        _ request: SuggestedReplyGenerationRequest,
        using context: AIProviderExecutionContext
    ) async throws -> SuggestedReplyGenerationResult {
        guard context.capability == .suggestedReplies else {
            throw AIServiceError.unsupportedCapability
        }
        let (adapter, apiKey) = try resolve(context)
        return try await adapter.generateSuggestedReplies(
            request,
            apiKey: apiKey,
            model: context.effectiveModel
        )
    }

    private func resolve(
        _ expected: AIProviderExecutionContext
    ) throws -> (any AIProviderAdapter, String) {
        let current = try activeContext(requiring: expected.capability)
        guard current == expected else {
            throw CancellationError()
        }
        guard let providerConfiguration,
            let apiKey = providerConfiguration.savedAPIKey(for: current.platform),
            !apiKey.isEmpty
        else {
            throw AIServiceError.missingAPIKey
        }
        guard let adapter = registry.adapter(for: current.platform) else {
            throw AIServiceError.unsupportedProvider
        }
        return (adapter, apiKey)
    }
}
