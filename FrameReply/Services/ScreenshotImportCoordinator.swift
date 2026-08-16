//
//  ScreenshotImportCoordinator.swift
//  FrameReply
//

import Foundation

struct PreparedScreenshotImport {
    let analysis: ChatImportAnalysis
    let matchDecision: ChatImportMatchDecision
    let traceID: ImportTraceID

    var confirmedChatID: String? { matchDecision.automaticChatID }
}

nonisolated enum ChatImportInputSource: Equatable, Sendable {
    case images
    case copiedText
}

nonisolated enum ScreenshotImportError: LocalizedError, Equatable, Sendable {
    case noImage
    case noTranscript
    case noMessages(source: ChatImportInputSource)
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
        case .noMessages(let source):
            switch source {
            case .images:
                String(localized: AppStrings.Errors.Import.noMessagesInImages)
            case .copiedText:
                String(localized: AppStrings.Errors.Import.noMessagesInCopiedText)
            }
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
        case .noMessages:
            "no_messages"
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
    private let destinationChatID: String?

    init(
        aiService: any AIServiceProviding,
        repository: ChatRepository,
        eventReporter: any ImportEventReporting = OSLogImportEventReporter(),
        destinationChatID: String? = nil
    ) {
        self.aiService = aiService
        self.repository = repository
        self.eventReporter = eventReporter
        self.destinationChatID = destinationChatID
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
        let prepared = try await prepare(imageDataList: imageDataList, traceID: traceID)
        return try commit(prepared)
    }

    func prepare(
        imageDataList: [Data],
        traceID: ImportTraceID = ImportTraceID()
    ) async throws -> PreparedScreenshotImport {
        let normalized = try ScreenshotImageNormalizer.normalize(imageDataList)
        return try await prepare(payload: .screenshots(normalized), traceID: traceID)
    }

    func process(
        transcriptItems: [String],
        traceID: ImportTraceID = ImportTraceID()
    ) async throws -> ScreenshotImportOutcome {
        let prepared = try await prepare(transcriptItems: transcriptItems, traceID: traceID)
        return try commit(prepared)
    }

    func prepare(
        transcriptItems: [String],
        traceID: ImportTraceID = ImportTraceID()
    ) async throws -> PreparedScreenshotImport {
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
        return try await prepare(payload: .sharedTranscript(transcript), traceID: traceID)
    }

    func commit(_ prepared: PreparedScreenshotImport) throws -> ScreenshotImportOutcome {
        try Task.checkCancellation()
        eventReporter.record(
            .stageStarted(traceID: prepared.traceID, stage: .persistence)
        )
        do {
            let outcome = try repository.applyImport(
                analysis: prepared.analysis,
                matchDecision: prepared.matchDecision,
                traceID: prepared.traceID
            )
            eventReporter.record(
                .importCompleted(
                    traceID: prepared.traceID,
                    matchedExisting: outcome.matchedExisting,
                    reviewRequired: outcome.reviewRequired,
                    duplicate: outcome.duplicate,
                    insertedMessageCount: outcome.insertedMessageCount
                )
            )
            return outcome
        } catch {
            eventReporter.record(
                .importFailed(
                    traceID: prepared.traceID,
                    stage: .persistence,
                    errorCode: "import_failed"
                )
            )
            throw error
        }
    }

    private func prepare(
        payload: ChatImportPayload,
        traceID: ImportTraceID
    ) async throws -> PreparedScreenshotImport {
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
                selfAliases: try repository.selfAliases().map(\.displayLabel),
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
                normalizeVisualOwnership: request.sharedTranscript == nil,
                maximumMessageCount: request.sharedTranscript == nil
                    ? nil : SharedTranscriptInput.maximumEstimatedMessageCount
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

        guard analysis.extractionStatus == .ok, !analysis.messages.isEmpty else {
            let source: ChatImportInputSource =
                switch payload {
                case .screenshots: .images
                case .sharedTranscript: .copiedText
                }
            let error = ScreenshotImportError.noMessages(source: source)
            eventReporter.record(
                .importFailed(
                    traceID: traceID,
                    stage: .provider,
                    errorCode: error.code
                )
            )
            throw error
        }

        let matchDecision: ChatImportMatchDecision
        if let destinationChatID {
            matchDecision = .automatic(destinationChatID)
        } else {
            eventReporter.record(.stageStarted(traceID: traceID, stage: .matching))
            matchDecision = ChatImportMatcher.decision(
                analysis: analysis,
                candidates: candidates
            )
        }

        return PreparedScreenshotImport(
            analysis: analysis,
            matchDecision: matchDecision,
            traceID: traceID
        )
    }
}

@MainActor
protocol ProviderConfigurationProviding: AnyObject {
    var activeProvider: ProviderConnection? { get }
    func savedAPIKey(for platform: ProviderPlatform) -> String?
    func hasValidDataConsent(for platform: ProviderPlatform) -> Bool
}

extension ProviderStore: ProviderConfigurationProviding {}
