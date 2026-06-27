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
    private let eventReporter: any ImportEventReporting

    convenience init() {
        let eventReporter = OSLogImportEventReporter()
        self.init(
            ocrService: VisionScreenshotOCRService(),
            providerStore: ProviderStore(),
            repository: ChatRepository(),
            eventReporter: eventReporter,
            clientResolver: { platform in
                switch platform {
                case .openAI:
                    OpenAIClient(eventReporter: eventReporter)
                case .deepSeek:
                    DeepSeekClient(eventReporter: eventReporter)
                }
            }
        )
    }

    init(
        ocrService: any ScreenshotOCRService,
        providerStore: any ProviderConfigurationProviding,
        repository: ChatRepository,
        eventReporter: any ImportEventReporting = OSLogImportEventReporter(),
        clientResolver: @escaping ClientResolver
    ) {
        self.ocrService = ocrService
        self.providerStore = providerStore
        self.repository = repository
        self.eventReporter = eventReporter
        self.clientResolver = clientResolver
    }

    func process(
        imageData: Data,
        traceID: ImportTraceID = ImportTraceID()
    ) async throws -> ScreenshotImportOutcome {
        eventReporter.record(.stageStarted(traceID: traceID, stage: .shortcut))
        guard let activeProvider = providerStore.activeProvider else {
            eventReporter.record(.importFailed(traceID: traceID, stage: .shortcut, errorCode: "no_provider"))
            throw ScreenshotImportError.noActiveProvider
        }
        guard let apiKey = providerStore.savedAPIKey(for: activeProvider.platform), !apiKey.isEmpty else {
            eventReporter.record(.importFailed(traceID: traceID, stage: .shortcut, errorCode: "missing_api_key"))
            throw ScreenshotImportError.missingAPIKey
        }
        guard let client = clientResolver(activeProvider.platform) else {
            eventReporter.record(.importFailed(traceID: traceID, stage: .shortcut, errorCode: "unsupported_provider"))
            throw ScreenshotImportError.unsupportedProvider
        }

        eventReporter.record(.stageStarted(traceID: traceID, stage: .ocr))
        let ocrStartedAt = Date()
        let document: OCRDocument
        do {
            document = try await ocrService.recognizeText(in: imageData)
        } catch {
            eventReporter.record(.importFailed(traceID: traceID, stage: .ocr, errorCode: "ocr_failed"))
            throw error
        }
        eventReporter.record(
            .ocrCompleted(
                traceID: traceID,
                durationMilliseconds: Int(Date().timeIntervalSince(ocrStartedAt) * 1_000),
                lineCount: document.lines.count
            )
        )

        try repository.seedIfNeeded()
        let candidates = try repository.matchCandidates()
        let request = ChatScreenshotAnalysisRequest(
            document: document,
            candidates: candidates,
            traceID: traceID
        )
        eventReporter.record(.stageStarted(traceID: traceID, stage: .provider))
        let analysis: ChatImportAnalysis
        do {
            let providerAnalysis = try await client.analyzeChatScreenshot(
                request,
                apiKey: apiKey,
                model: activeProvider.model
            )
            analysis = try ChatImportAnalysisDecoder.validate(
                providerAnalysis,
                candidateIDs: Set(candidates.map(\.id))
            )
        } catch let failure as StructuredOutputFailure {
            let error = ProviderConnectionError.structuredOutput(
                ProviderStructuredOutputError(
                    provider: activeProvider.platform.rawValue,
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
        let confirmedChatID = ChatImportMatcher.confirmedChatID(
            analysis: analysis,
            candidates: candidates
        )

        eventReporter.record(.stageStarted(traceID: traceID, stage: .persistence))
        do {
            let outcome = try repository.applyImport(
                analysis: analysis,
                confirmedChatID: confirmedChatID,
                provider: activeProvider.platform,
                model: activeProvider.model,
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
