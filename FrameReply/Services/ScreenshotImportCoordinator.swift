//
//  ScreenshotImportCoordinator.swift
//  FrameReply
//

import Foundation

enum ScreenshotImportError: LocalizedError {
    case noImage
    case noTranscript
    case transcriptTooLarge
    case tooManyImages
    case unsupportedImage
    case imagePayloadTooLarge
    case noActiveProvider
    case missingAPIKey
    case consentRequired
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .noImage:
            String(localized: AppStrings.Errors.Import.noImage)
        case .noTranscript:
            String(localized: AppStrings.Errors.Import.noTranscript)
        case .transcriptTooLarge:
            String(localized: AppStrings.Errors.Import.transcriptTooLarge)
        case .tooManyImages:
            String(localized: AppStrings.Errors.Import.tooManyImages)
        case .unsupportedImage:
            String(localized: AppStrings.Errors.Import.unsupportedImage)
        case .imagePayloadTooLarge:
            String(localized: AppStrings.Errors.Import.imagesTooLarge)
        case .noActiveProvider:
            String(localized: AppStrings.Errors.Import.noProvider)
        case .missingAPIKey:
            String(localized: AppStrings.Errors.AI.missingKey)
        case .consentRequired:
            String(localized: AppStrings.Errors.Import.consentRequired)
        case .unsupportedProvider:
            String(localized: AppStrings.Errors.Import.unsupportedProvider)
        }
    }

    var code: String {
        switch self {
        case .noImage:
            "no_image"
        case .noTranscript:
            "no_transcript"
        case .transcriptTooLarge:
            "transcript_too_large"
        case .tooManyImages:
            "too_many_images"
        case .unsupportedImage:
            "unsupported_image"
        case .imagePayloadTooLarge:
            "image_payload_too_large"
        case .noActiveProvider:
            "no_provider"
        case .missingAPIKey:
            "missing_api_key"
        case .consentRequired:
            "provider_consent_required"
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
        case .consentRequired:
            self = .consentRequired
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
        try await process(imageDataList: [imageData], traceID: traceID)
    }

    func process(
        imageDataList: [Data],
        traceID: ImportTraceID = ImportTraceID()
    ) async throws -> ScreenshotImportOutcome {
        let normalized = try ScreenshotImageNormalizer.normalize(imageDataList)
        return try await process(payload: .screenshots(normalized), traceID: traceID)
    }

    func process(
        transcriptItems: [String],
        traceID: ImportTraceID = ImportTraceID()
    ) async throws -> ScreenshotImportOutcome {
        let items = transcriptItems.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !items.isEmpty else {
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .shortcut, errorCode: "no_transcript")
            )
            throw ScreenshotImportError.noTranscript
        }
        let transcript = SharedTranscriptInput(items: items)
        guard transcript.characterCount <= SharedTranscriptInput.maximumCharacterCount,
            transcript.items.count <= SharedTranscriptInput.maximumItemCount,
            transcript.estimatedMessageCount <= SharedTranscriptInput.maximumEstimatedMessageCount
        else {
            eventReporter.record(
                .importFailed(
                    traceID: traceID,
                    stage: .shortcut,
                    errorCode: "transcript_too_large"
                )
            )
            throw ScreenshotImportError.transcriptTooLarge
        }
        return try await process(payload: .sharedTranscript(transcript), traceID: traceID)
    }

    private func process(
        payload: ChatImportPayload,
        traceID: ImportTraceID
    ) async throws -> ScreenshotImportOutcome {
        eventReporter.record(.stageStarted(traceID: traceID, stage: .shortcut))
        if case .screenshots(let imageDataList) = payload, imageDataList.isEmpty {
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .shortcut, errorCode: "no_image")
            )
            throw ScreenshotImportError.noImage
        }
        let providerContext: AIProviderExecutionContext
        do {
            let capability: AIProviderCapability =
                switch payload {
                case .screenshots: .screenshotAnalysis
                case .sharedTranscript: .transcriptAnalysis
                }
            providerContext = try aiService.activeContext(requiring: capability)
        } catch let error as AIServiceError {
            let importError = ScreenshotImportError(error)
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .shortcut, errorCode: importError.code)
            )
            throw importError
        }

        try repository.seedIfNeeded()
        let candidates = try repository.matchCandidates()
        let request: ChatImportAnalysisRequest
        switch payload {
        case .screenshots(let imageDataList):
            request = ChatImportAnalysisRequest(
                imageDataList: imageDataList,
                candidates: candidates,
                traceID: traceID
            )
        case .sharedTranscript(let transcript):
            request = ChatImportAnalysisRequest(
                transcriptItems: transcript.items,
                candidates: candidates,
                traceID: traceID
            )
        }
        eventReporter.record(.stageStarted(traceID: traceID, stage: .provider))
        let analysis: ChatImportAnalysis
        do {
            let providerAnalysis = try await aiService.analyzeChatScreenshot(
                request,
                using: providerContext
            )
            analysis = try ChatImportAnalysisDecoder.validate(
                providerAnalysis,
                candidateIDs: Set(candidates.map(\.id)),
                normalizeVisualOwnership: request.sharedTranscript == nil
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
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .provider, errorCode: "provider_error"))
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
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .persistence, errorCode: "import_failed"))
            throw error
        }
    }
}

@MainActor
protocol ProviderConfigurationProviding: AnyObject {
    var activeProvider: ProviderConnection? { get }
    func savedAPIKey(for platform: ProviderPlatform) -> String?
    func hasValidDataConsent(for platform: ProviderPlatform) -> Bool
}

extension ProviderStore: ProviderConfigurationProviding {}
