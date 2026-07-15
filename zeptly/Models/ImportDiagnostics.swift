//
//  ImportDiagnostics.swift
//  zeptly
//

import Foundation
import OSLog

nonisolated struct ImportTraceID: Codable, Equatable, Hashable, Sendable {
    let value: UUID

    init(value: UUID = UUID()) {
        self.value = value
    }

    var diagnosticID: String {
        String(value.uuidString.prefix(8)).uppercased()
    }
}

nonisolated enum ImportStage: String, Sendable {
    case shortcut
    case screenshotDecoding = "screenshot_decoding"
    case provider
    case matching
    case persistence
    case replyGeneration = "reply_generation"
}

nonisolated enum StructuredOutputFailureKind: String, Codable, Equatable, Sendable {
    case emptyResponse = "empty_response"
    case truncatedResponse = "truncated_response"
    case invalidJSON = "invalid_json"
    case schemaMismatch = "schema_mismatch"
    case invalidCandidateID = "invalid_candidate_id"
    case incompleteMessages = "incomplete_messages"

    var shortcutErrorCode: String {
        "provider_\(rawValue)"
    }
}

nonisolated struct StructuredOutputFailure: Error, Equatable, Sendable {
    let kind: StructuredOutputFailureKind
    let codingPath: String?
}

nonisolated struct ProviderStructuredOutputError: Error, Equatable, Sendable {
    let provider: String
    let traceID: ImportTraceID
    let failure: StructuredOutputFailure
}

/// Deliberately contains metadata only. There is no field capable of carrying image or chat data.
nonisolated enum ImportEvent: Equatable, Sendable {
    case stageStarted(traceID: ImportTraceID, stage: ImportStage)
    case providerAttempt(
        traceID: ImportTraceID,
        provider: String,
        model: String,
        attempt: Int,
        maxTokens: Int
    )
    case providerResponse(
        traceID: ImportTraceID,
        provider: String,
        model: String,
        attempt: Int,
        durationMilliseconds: Int,
        httpStatus: Int?,
        requestID: String?,
        finishReason: String?,
        byteCount: Int,
        inputTokens: Int?,
        outputTokens: Int?,
        cachedInputTokens: Int?
    )
    case contractValidation(
        traceID: ImportTraceID,
        provider: String,
        contract: String,
        version: Int,
        attempt: Int,
        category: String
    )
    case structuredOutputFailure(
        traceID: ImportTraceID,
        provider: String,
        attempt: Int,
        kind: StructuredOutputFailureKind,
        codingPath: String?
    )
    case importCompleted(
        traceID: ImportTraceID,
        matchedExisting: Bool,
        reviewRequired: Bool,
        duplicate: Bool,
        insertedMessageCount: Int
    )
    case importFailed(traceID: ImportTraceID, stage: ImportStage, errorCode: String)
}

nonisolated protocol ImportEventReporting: Sendable {
    func record(_ event: ImportEvent)
}

nonisolated struct OSLogImportEventReporter: ImportEventReporting {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gigabeyond.zeptly",
        category: "ScreenshotImport"
    )

    func record(_ event: ImportEvent) {
        switch event {
        case .stageStarted(let traceID, let stage):
            logger.info(
                "trace=\(traceID.diagnosticID, privacy: .private) stage=\(stage.rawValue, privacy: .public) event=started"
            )
        case .providerAttempt(let traceID, let provider, let model, let attempt, let maxTokens):
            logger.info(
                "trace=\(traceID.diagnosticID, privacy: .private) stage=provider event=attempt provider=\(provider, privacy: .private) model=\(model, privacy: .private) attempt=\(attempt) max_tokens=\(maxTokens)"
            )
        case .providerResponse(
            let traceID, let provider, let model, let attempt, let duration, let status,
            let requestID, let finishReason, let byteCount, let inputTokens, let outputTokens,
            let cachedInputTokens):
            logger.info(
                "trace=\(traceID.diagnosticID, privacy: .private) stage=provider event=response provider=\(provider, privacy: .private) model=\(model, privacy: .private) attempt=\(attempt) duration_ms=\(duration) status=\(status ?? 0) request_id=\(requestID ?? "none", privacy: .private) finish_reason=\(finishReason ?? "none", privacy: .private) bytes=\(byteCount) input_tokens=\(inputTokens ?? 0) output_tokens=\(outputTokens ?? 0) cached_input_tokens=\(cachedInputTokens ?? 0)"
            )
        case .contractValidation(
            let traceID, let provider, let contract, let version, let attempt, let category):
            logger.info(
                "trace=\(traceID.diagnosticID, privacy: .private) stage=provider event=contract_validation provider=\(provider, privacy: .private) contract=\(contract, privacy: .private) version=\(version) attempt=\(attempt) category=\(category, privacy: .private)"
            )
        case .structuredOutputFailure(
            let traceID, let provider, let attempt, let kind, let codingPath):
            logger.error(
                "trace=\(traceID.diagnosticID, privacy: .private) stage=provider event=decode_failed provider=\(provider, privacy: .private) attempt=\(attempt) kind=\(kind.rawValue, privacy: .private) path=\(codingPath ?? "none", privacy: .private)"
            )
        case .importCompleted(
            let traceID, let matchedExisting, let reviewRequired, let duplicate,
            let insertedMessageCount):
            logger.info(
                "trace=\(traceID.diagnosticID, privacy: .private) stage=persistence event=completed matched=\(matchedExisting) review=\(reviewRequired) duplicate=\(duplicate) inserted=\(insertedMessageCount)"
            )
        case .importFailed(let traceID, let stage, let errorCode):
            logger.error(
                "trace=\(traceID.diagnosticID, privacy: .private) stage=\(stage.rawValue, privacy: .public) event=failed code=\(errorCode, privacy: .private)"
            )
        }
    }
}

nonisolated enum ShortcutLifecycleStage: String, Sendable {
    case analysisStarted = "analysis_started"
    case analysisCompleted = "analysis_completed"
    case inputChoiceDisplayed = "input_choice_displayed"
    case inputPromptDisplayed = "input_prompt_displayed"
    case inputSubmitted = "input_submitted"
    case inputSkipped = "input_skipped"
    case inputCancelled = "input_cancelled"
    case stateCommitted = "state_committed"
    case analyzeReturned = "analyze_returned"
    case generateStarted = "generate_started"
    case stateObserved = "state_observed"
    case contextConsumed = "context_consumed"
}

/// Records only workflow metadata. Screenshot pixels and user-entered text are
/// intentionally not accepted by this API.
nonisolated struct ShortcutLifecycleReporter: Sendable {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gigabeyond.zeptly",
        category: "ShortcutLifecycle"
    )

    func record(
        _ stage: ShortcutLifecycleStage,
        operationID: UUID,
        startedAt: Date,
        state: DraftingInputState? = nil,
        hasInput: Bool? = nil
    ) {
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        let operation = operationID.uuidString.prefix(8).uppercased()
        let stateValue = state?.rawValue ?? "none"
        let inputValue = hasInput ?? false
        logger.info(
            "operation=\(operation, privacy: .private) event=\(stage.rawValue, privacy: .public) elapsed_ms=\(elapsed) state=\(stateValue, privacy: .private) has_input=\(inputValue)"
        )
    }
}

nonisolated enum ChatImportDebugLogger {
    static func structuredOutputFailure(
        _ failure: StructuredOutputFailure,
        traceID: ImportTraceID,
        provider: String,
        model: String,
        attempt: Int,
        finishReason: String?,
        content: String?
    ) {
        #if DEBUG
            let finish = finishReason ?? "none"
            let path = failure.codingPath ?? "none"
            Swift.print(
                "[ChatImportAI][decode-failed] trace=\(traceID.diagnosticID) provider=\(provider) model=\(model) attempt=\(attempt) finish=\(finish) kind=\(failure.kind.rawValue) path=\(path)"
            )
            Swift.print("[ChatImportAI][content-redacted] present=\(content?.isEmpty == false)")
        #endif
    }

    static func responseMetadata(
        traceID: ImportTraceID,
        provider: String,
        model: String,
        attempt: Int,
        finishReason: String?,
        content: String?
    ) {
        #if DEBUG
            let finish = finishReason ?? "none"
            let header =
                "[ChatScreenshotAI][response] trace=\(traceID.diagnosticID) provider=\(provider) model=\(model) attempt=\(attempt) finish=\(finish)"
            Swift.print(header)
            Swift.print("[ChatScreenshotAI][content-redacted] present=\(content?.isEmpty == false)")
        #endif
    }

    static func normalized(
        _ analysis: ChatImportAnalysis,
        traceID: ImportTraceID,
        provider: String,
        model: String,
        attempt: Int
    ) {
        #if DEBUG
            Swift.print(
                "[ChatScreenshotAI][normalized] trace=\(traceID.diagnosticID) provider=\(provider) model=\(model) attempt=\(attempt) messages=\(analysis.messages.count)"
            )
        #endif
    }

    static func normalization(notes: [String]) {
        #if DEBUG
            Swift.print("[ChatScreenshotAI][sender-correction] count=\(notes.count)")
        #endif
    }
}
