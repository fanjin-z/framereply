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
    case ocr
    case provider
    case matching
    case persistence
}

nonisolated enum StructuredOutputFailureKind: String, Codable, Equatable, Sendable {
    case emptyResponse = "empty_response"
    case truncatedResponse = "truncated_response"
    case invalidJSON = "invalid_json"
    case schemaMismatch = "schema_mismatch"
    case invalidCandidateID = "invalid_candidate_id"
    case incompleteMessages = "incomplete_messages"

    var isRetryable: Bool {
        switch self {
        case .emptyResponse, .truncatedResponse, .invalidJSON, .schemaMismatch:
            true
        case .invalidCandidateID, .incompleteMessages:
            false
        }
    }

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

/// Deliberately contains metadata only. There is no field capable of carrying OCR or chat text.
nonisolated enum ImportEvent: Equatable, Sendable {
    case stageStarted(traceID: ImportTraceID, stage: ImportStage)
    case ocrCompleted(traceID: ImportTraceID, durationMilliseconds: Int, lineCount: Int)
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
        byteCount: Int
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
        case let .stageStarted(traceID, stage):
            logger.info("trace=\(traceID.diagnosticID, privacy: .public) stage=\(stage.rawValue, privacy: .public) event=started")
        case let .ocrCompleted(traceID, duration, lineCount):
            logger.info("trace=\(traceID.diagnosticID, privacy: .public) stage=ocr event=completed duration_ms=\(duration) lines=\(lineCount)")
        case let .providerAttempt(traceID, provider, model, attempt, maxTokens):
            logger.info("trace=\(traceID.diagnosticID, privacy: .public) stage=provider event=attempt provider=\(provider, privacy: .public) model=\(model, privacy: .public) attempt=\(attempt) max_tokens=\(maxTokens)")
        case let .providerResponse(traceID, provider, model, attempt, duration, status, requestID, finishReason, byteCount):
            logger.info("trace=\(traceID.diagnosticID, privacy: .public) stage=provider event=response provider=\(provider, privacy: .public) model=\(model, privacy: .public) attempt=\(attempt) duration_ms=\(duration) status=\(status ?? 0) request_id=\(requestID ?? "none", privacy: .public) finish_reason=\(finishReason ?? "none", privacy: .public) bytes=\(byteCount)")
        case let .structuredOutputFailure(traceID, provider, attempt, kind, codingPath):
            logger.error("trace=\(traceID.diagnosticID, privacy: .public) stage=provider event=decode_failed provider=\(provider, privacy: .public) attempt=\(attempt) kind=\(kind.rawValue, privacy: .public) path=\(codingPath ?? "none", privacy: .public)")
        case let .importCompleted(traceID, matchedExisting, reviewRequired, duplicate, insertedMessageCount):
            logger.info("trace=\(traceID.diagnosticID, privacy: .public) stage=persistence event=completed matched=\(matchedExisting) review=\(reviewRequired) duplicate=\(duplicate) inserted=\(insertedMessageCount)")
        case let .importFailed(traceID, stage, errorCode):
            logger.error("trace=\(traceID.diagnosticID, privacy: .public) stage=\(stage.rawValue, privacy: .public) event=failed code=\(errorCode, privacy: .public)")
        }
    }
}
