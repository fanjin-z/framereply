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

    init(_ error: AIServiceError) {
        switch error {
        case .noActiveProvider:
            self = .noActiveProvider
        case .missingAPIKey:
            self = .missingAPIKey
        case .unsupportedProvider, .unsupportedCapability:
            self = .unsupportedProvider
        }
    }
}

@MainActor
final class ScreenshotImportCoordinator {
    private let aiService: any AIServiceProviding
    private let repository: ChatRepository
    private let eventReporter: any ImportEventReporting

    convenience init() {
        let eventReporter = OSLogImportEventReporter()
        let providerStore = ProviderStore()
        self.init(
            aiService: AIService(
                providerConfiguration: providerStore,
                registry: .live(eventReporter: eventReporter)
            ),
            repository: ChatRepository(),
            eventReporter: eventReporter
        )
    }

    init(
        aiService: any AIServiceProviding,
        repository: ChatRepository,
        eventReporter: any ImportEventReporting = OSLogImportEventReporter()
    ) {
        self.aiService = aiService
        self.repository = repository
        self.eventReporter = eventReporter
    }

    func process(
        imageData: Data,
        traceID: ImportTraceID = ImportTraceID()
    ) async throws -> ScreenshotImportOutcome {
        eventReporter.record(.stageStarted(traceID: traceID, stage: .shortcut))
        let providerContext: AIProviderExecutionContext
        do {
            providerContext = try aiService.activeContext(requiring: .screenshotAnalysis)
        } catch let error as AIServiceError {
            let importError = ScreenshotImportError(error)
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .shortcut, errorCode: importError.code)
            )
            throw importError
        }

        try repository.seedIfNeeded()
        let candidates = try repository.matchCandidates()
        let request = ChatScreenshotAnalysisRequest(
            imageData: imageData,
            candidates: candidates,
            traceID: traceID
        )
        eventReporter.record(.stageStarted(traceID: traceID, stage: .provider))
        let analysis: ChatImportAnalysis
        do {
            let providerAnalysis = try await aiService.analyzeChatScreenshot(
                request,
                using: providerContext
            )
            analysis = try ChatImportAnalysisDecoder.validate(
                providerAnalysis,
                candidateIDs: Set(candidates.map(\.id))
            )
        } catch let failure as StructuredOutputFailure {
            let error = ProviderConnectionError.structuredOutput(
                ProviderStructuredOutputError(
                    provider: providerContext.platform.rawValue,
                    traceID: traceID,
                    failure: failure
                )
            )
            eventReporter.record(
                .importFailed(
                    traceID: traceID,
                    stage: .provider,
                    errorCode: error.shortcutErrorCode
                )
            )
            throw error
        } catch let error as AIServiceError {
            let importError = ScreenshotImportError(error)
            eventReporter.record(
                .importFailed(
                    traceID: traceID,
                    stage: .provider,
                    errorCode: importError.code
                )
            )
            throw importError
        } catch let error as ProviderConnectionError {
            eventReporter.record(
                .importFailed(
                    traceID: traceID,
                    stage: .provider,
                    errorCode: error.shortcutErrorCode
                )
            )
            throw error
        } catch {
            eventReporter.record(.importFailed(traceID: traceID, stage: .provider, errorCode: "provider_error"))
            throw error
        }

        eventReporter.record(.stageStarted(traceID: traceID, stage: .matching))
        let avatarArtifact = AvatarIdentityService.extract(
            from: imageData,
            bounds: analysis.avatarBounds
        )
        let matchDecision = ChatImportMatcher.decision(
            analysis: analysis,
            candidates: candidates,
            avatarArtifact: avatarArtifact,
            storedAvatars: try repository.storedAvatarFingerprints()
        )

        eventReporter.record(.stageStarted(traceID: traceID, stage: .persistence))
        do {
            let outcome = try repository.applyImport(
                analysis: analysis,
                confirmedChatID: matchDecision.confirmedChatID,
                matchDecision: matchDecision,
                avatarArtifact: avatarArtifact,
                provider: providerContext.platform,
                model: providerContext.effectiveModel,
                traceID: traceID
            )
            eventReporter.record(
                .importCompleted(
                    traceID: traceID,
                    matchedExisting: outcome.matchedExisting,
                    reviewRequired: outcome.reviewRequired,
                    duplicate: outcome.duplicate,
                    insertedMessageCount: outcome.insertedMessageCount
                )
            )
            return outcome
        } catch {
            eventReporter.record(.importFailed(traceID: traceID, stage: .persistence, errorCode: "import_failed"))
            throw error
        }
    }
}

@MainActor
protocol ProviderConfigurationProviding: AnyObject {
    var activeProvider: ProviderConnection? { get }
    func savedAPIKey(for platform: ProviderPlatform) -> String?
}

extension ProviderStore: ProviderConfigurationProviding {}
