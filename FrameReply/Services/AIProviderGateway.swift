import Foundation

enum StructuredOutputCapability: Equatable {
    case strictJSONSchema
    case jsonObject
}

struct AIOutputContract {
    let name: String
    let version: Int
    let instructions: String
    let schema: [String: Any]

    func instructions(for capability: StructuredOutputCapability) -> String {
        guard capability == .jsonObject,
            let data = try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]),
            let compactSchema = String(data: data, encoding: .utf8)
        else {
            return instructions
        }
        return "\(instructions)\nReturn JSON matching this exact schema: \(compactSchema)"
    }
}

nonisolated enum AIProviderCapability: Sendable {
    case screenshotAnalysis
    case transcriptAnalysis
    case suggestedReplies
}

nonisolated struct ProviderModelProfile: Equatable, Sendable {
    let screenshotAnalysisModel: ProviderModel?
    let transcriptAnalysisModel: ProviderModel?
    let suggestedReplyModel: ProviderModel?

    func model(for capability: AIProviderCapability) -> ProviderModel? {
        switch capability {
        case .screenshotAnalysis:
            screenshotAnalysisModel
        case .transcriptAnalysis:
            transcriptAnalysisModel
        case .suggestedReplies:
            suggestedReplyModel
        }
    }
}

@MainActor
protocol AIProviderAdapter: ProviderValidator, ChatScreenshotAnalyzing, SuggestedReplyGenerating {
    var platform: ProviderPlatform { get }
    func modelProfile(for selectedTier: ProviderTier) -> ProviderModelProfile?
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
        let adapters: [any AIProviderAdapter] = [
            OpenAIClient(eventReporter: eventReporter),
            ZAIClient(region: .international, eventReporter: eventReporter),
            ZAIClient(region: .china, eventReporter: eventReporter)
        ]
        return AIProviderRegistry(adapters: adapters)
    }

    func adapter(for platform: ProviderPlatform) -> (any AIProviderAdapter)? {
        adapters[platform]
    }

    func profile(
        for platform: ProviderPlatform,
        selectedTier: ProviderTier
    ) -> ProviderModelProfile? {
        adapters[platform]?.modelProfile(for: selectedTier)
    }
}

nonisolated struct AIProviderExecutionContext: Equatable, Sendable {
    let platform: ProviderPlatform
    let capability: AIProviderCapability
    let effectiveModel: ProviderModel
}

nonisolated enum AIServiceError: LocalizedError, Sendable {
    case noActiveProvider
    case missingAPIKey
    case consentRequired
    case unsupportedProvider
    case unsupportedCapability

    var errorDescription: String? {
        switch self {
        case .noActiveProvider:
            String(localized: AppStrings.Errors.AI.noProvider)
        case .missingAPIKey:
            String(localized: AppStrings.Errors.AI.missingKey)
        case .consentRequired:
            String(localized: AppStrings.Errors.AI.consentRequired)
        case .unsupportedProvider:
            String(localized: AppStrings.Errors.AI.unsupportedProvider)
        case .unsupportedCapability:
            String(localized: AppStrings.Errors.AI.unsupportedCapability)
        }
    }

    var code: String {
        switch self {
        case .noActiveProvider: "no_provider"
        case .missingAPIKey: "missing_api_key"
        case .consentRequired: "provider_consent_required"
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
        selectedTier: ProviderTier,
        apiKey: String
    ) async throws {
        guard let adapter = registry.adapter(for: platform) else {
            throw AIServiceError.unsupportedProvider
        }
        guard let profile = adapter.modelProfile(for: selectedTier),
            let validationModel =
                profile.screenshotAnalysisModel ?? profile.transcriptAnalysisModel
                ?? profile.suggestedReplyModel
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
            let profile = adapter.modelProfile(for: connection.tier)
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
        guard providerConfiguration.hasValidDataConsent(for: connection.platform) else {
            throw AIServiceError.consentRequired
        }
        return AIProviderExecutionContext(
            platform: connection.platform,
            capability: capability,
            effectiveModel: effectiveModel
        )
    }

    func analyzeChatScreenshot(
        _ request: ChatScreenshotAnalysisRequest,
        using context: AIProviderExecutionContext
    ) async throws -> ChatImportAnalysis {
        let requiredCapability: AIProviderCapability =
            request.sharedTranscript == nil ? .screenshotAnalysis : .transcriptAnalysis
        guard context.capability == requiredCapability else {
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
