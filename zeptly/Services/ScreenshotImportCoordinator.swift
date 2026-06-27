//
//  ScreenshotImportCoordinator.swift
//  zeptly
//

import Foundation

enum ScreenshotImportError: LocalizedError {
    case noActiveProvider
    case missingAPIKey
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .noActiveProvider:
            "Connect and select a model provider before importing a screenshot."
        case .missingAPIKey:
            "The selected provider API key is unavailable. Reconnect it in Settings."
        case .unsupportedProvider:
            "The selected provider cannot analyze chat screenshots."
        }
    }

    var code: String {
        switch self {
        case .noActiveProvider:
            "no_provider"
        case .missingAPIKey:
            "missing_api_key"
        case .unsupportedProvider:
            "unsupported_provider"
        }
    }
}

@MainActor
final class ScreenshotImportCoordinator {
    typealias ClientResolver = (ProviderPlatform) -> (any AIProviderClient)?

    private let ocrService: any ScreenshotOCRService
    private let providerStore: any ProviderConfigurationProviding
    private let repository: ChatRepository
    private let clientResolver: ClientResolver

    convenience init() {
        self.init(
            ocrService: VisionScreenshotOCRService(),
            providerStore: ProviderStore(),
            repository: ChatRepository(),
            clientResolver: { platform in
                switch platform {
                case .openAI:
                    OpenAIClient()
                case .deepSeek:
                    DeepSeekClient()
                }
            }
        )
    }

    init(
        ocrService: any ScreenshotOCRService,
        providerStore: any ProviderConfigurationProviding,
        repository: ChatRepository,
        clientResolver: @escaping ClientResolver
    ) {
        self.ocrService = ocrService
        self.providerStore = providerStore
        self.repository = repository
        self.clientResolver = clientResolver
    }

    func process(imageData: Data) async throws -> ScreenshotImportOutcome {
        guard let activeProvider = providerStore.activeProvider else {
            throw ScreenshotImportError.noActiveProvider
        }
        guard let apiKey = providerStore.savedAPIKey(for: activeProvider.platform), !apiKey.isEmpty else {
            throw ScreenshotImportError.missingAPIKey
        }
        guard let client = clientResolver(activeProvider.platform) else {
            throw ScreenshotImportError.unsupportedProvider
        }

        let document = try await ocrService.recognizeText(in: imageData)
        try repository.seedIfNeeded()
        let candidates = try repository.matchCandidates()
        let request = ChatScreenshotAnalysisRequest(document: document, candidates: candidates)
        let providerAnalysis = try await client.analyzeChatScreenshot(
            request,
            apiKey: apiKey,
            model: activeProvider.model
        )
        let analysis = try providerAnalysis.validated(candidateIDs: Set(candidates.map(\.id)))
        let confirmedChatID = ChatImportMatcher.confirmedChatID(
            analysis: analysis,
            candidates: candidates
        )

        return try repository.applyImport(
            analysis: analysis,
            confirmedChatID: confirmedChatID,
            provider: activeProvider.platform,
            model: activeProvider.model
        )
    }
}

@MainActor
protocol ProviderConfigurationProviding: AnyObject {
    var activeProvider: ProviderConnection? { get }
    func savedAPIKey(for platform: ProviderPlatform) -> String?
}

extension ProviderStore: ProviderConfigurationProviding {}
