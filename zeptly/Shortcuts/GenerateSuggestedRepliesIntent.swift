//
//  GenerateSuggestedRepliesIntent.swift
//  zeptly
//

import AppIntents
import Foundation
import SwiftData

nonisolated enum ShortcutResponseStatus: String, Codable, Equatable, Sendable {
    case success
    case fail
}

nonisolated enum ShortcutReplyStatus: String, Codable, Equatable, Sendable {
    case generated
    case cached
    case failed
}

nonisolated struct ShortcutResponsePayload: Codable, Equatable, Sendable {
    let status: ShortcutResponseStatus
    let message: String
    let diagnosticID: String
    let chatID: String?
    let chatName: String?
    let importID: UUID?
    let matchedExisting: Bool?
    let reviewRequired: Bool?
    let duplicate: Bool?
    let insertedMessageCount: Int?
    let errorCode: String?
    let suggestedReplies: [String]?
    let replyStatus: ShortcutReplyStatus?
    let replyErrorCode: String?

    init(
        status: ShortcutResponseStatus,
        message: String,
        diagnosticID: String,
        chatID: String?,
        chatName: String?,
        importID: UUID?,
        matchedExisting: Bool?,
        reviewRequired: Bool?,
        duplicate: Bool?,
        insertedMessageCount: Int?,
        errorCode: String?,
        suggestedReplies: [String]? = nil,
        replyStatus: ShortcutReplyStatus? = nil,
        replyErrorCode: String? = nil
    ) {
        self.status = status
        self.message = message
        self.diagnosticID = diagnosticID
        self.chatID = chatID
        self.chatName = chatName
        self.importID = importID
        self.matchedExisting = matchedExisting
        self.reviewRequired = reviewRequired
        self.duplicate = duplicate
        self.insertedMessageCount = insertedMessageCount
        self.errorCode = errorCode
        self.suggestedReplies = suggestedReplies
        self.replyStatus = replyStatus
        self.replyErrorCode = replyErrorCode
    }
}

nonisolated struct ShortcutResponsePresentation: Equatable, Sendable {
    let payload: ShortcutResponsePayload
    let dialog: String

    var json: String {
        guard
            let data = try? JSONEncoder().encode(payload),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{\"status\":\"fail\",\"message\":\"failed to encode response\"}"
        }
        return json
    }
}

nonisolated enum ShortcutResponseBuilder {
    static func success(
        _ outcome: ScreenshotImportOutcome,
        repliesOutcome: SuggestedRepliesOutcome? = nil,
        replyErrorCode: String? = nil
    ) -> ShortcutResponsePresentation {
        let count = outcome.insertedMessageCount
        let noun = count == 1 ? "message" : "messages"
        let message: String
        if outcome.duplicate {
            message = "No new messages found in \(outcome.chatName)."
        } else if outcome.reviewRequired {
            message = "Imported \(count) \(noun) as \(outcome.chatName). Review it in Zeptly."
        } else {
            message = "Added \(count) new \(noun) to \(outcome.chatName)."
        }

        let replies = repliesOutcome?.replies
        let replyStatus =
            repliesOutcome.map {
                switch $0.source {
                case .generated: ShortcutReplyStatus.generated
                case .cached: ShortcutReplyStatus.cached
                }
            } ?? .failed
        let dialog: String
        if let replies, replies.count == 2 {
            dialog = "\(message)\n\nSuggested replies:\n1. \(replies[0])\n2. \(replies[1])"
        } else {
            dialog = "\(message) Suggested replies are unavailable; open Zeptly to retry."
        }

        return ShortcutResponsePresentation(
            payload: ShortcutResponsePayload(
                status: .success,
                message: message,
                diagnosticID: outcome.diagnosticID,
                chatID: outcome.chatID,
                chatName: outcome.chatName,
                importID: outcome.importID,
                matchedExisting: outcome.matchedExisting,
                reviewRequired: outcome.reviewRequired,
                duplicate: outcome.duplicate,
                insertedMessageCount: count,
                errorCode: nil,
                suggestedReplies: replies,
                replyStatus: replyStatus,
                replyErrorCode: repliesOutcome == nil
                    ? (replyErrorCode ?? "reply_generation_failed") : nil
            ),
            dialog: dialog
        )
    }

    static func failure(
        message: String,
        errorCode: String,
        traceID: ImportTraceID
    ) -> ShortcutResponsePresentation {
        ShortcutResponsePresentation(
            payload: ShortcutResponsePayload(
                status: .fail,
                message: message,
                diagnosticID: traceID.diagnosticID,
                chatID: nil,
                chatName: nil,
                importID: nil,
                matchedExisting: nil,
                reviewRequired: nil,
                duplicate: nil,
                insertedMessageCount: nil,
                errorCode: errorCode,
                suggestedReplies: nil,
                replyStatus: nil,
                replyErrorCode: nil
            ),
            dialog: "\(message) Reference \(traceID.diagnosticID)."
        )
    }
}

struct GenerateSuggestedRepliesIntent: AppIntent {
    static let title: LocalizedStringResource = "Generate Suggested Replies"
    static let description = IntentDescription(
        "Generates two replies for a chat analyzed by Zeptly.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Analyzed Chat",
        description:
            "The output from Analyze Chat Images or Analyze Chat Text.",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var analyzedChat: AnalyzedChatEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Generate replies for \(\.$analyzedChat)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let fallbackTraceID = ImportTraceID()
        guard let analyzedChat else {
            let response = ShortcutResponseBuilder.failure(
                message: "No analyzed chat was provided.",
                errorCode: "no_prepared_chat",
                traceID: fallbackTraceID
            )
            return .result(value: response.dialog)
        }

        let eventReporter = OSLogImportEventReporter()
        let traceID = ImportTraceID(value: analyzedChat.operationID)
        let startedAt = Date()
        let lifecycleReporter = ShortcutLifecycleReporter()
        lifecycleReporter.record(
            .generateStarted, operationID: analyzedChat.operationID, startedAt: startedAt)
        eventReporter.record(.stageStarted(traceID: traceID, stage: .replyGeneration))
        do {
            let consumption = try await DraftingInputBarrier.waitUntilReady {
                let result = try await MainActor.run {
                    let repository = ChatRepository(context: ModelContext(ZeptlyDataStore.shared))
                    guard let record = try repository.importRecord(id: analyzedChat.id),
                        record.chatID == analyzedChat.chatID
                    else {
                        return DraftingInputConsumption.missing
                    }
                    return try repository.consumeDraftingInputIfReady(
                        importID: analyzedChat.id,
                        operationID: analyzedChat.operationID
                    )
                }
                let state: DraftingInputState? =
                    switch result {
                    case .pending: .pending
                    case .submitted: .submitted
                    case .skipped: .skipped
                    default: nil
                    }
                let hasInput: Bool
                if case .submitted = result {
                    hasInput = true
                } else {
                    hasInput = false
                }
                lifecycleReporter.record(
                    .stateObserved,
                    operationID: analyzedChat.operationID,
                    startedAt: startedAt,
                    state: state,
                    hasInput: hasInput
                )
                return result
            }

            let input: String?
            switch consumption {
            case .submitted(let value):
                input = value
                lifecycleReporter.record(
                    .contextConsumed,
                    operationID: analyzedChat.operationID,
                    startedAt: startedAt,
                    state: .submitted,
                    hasInput: true
                )
            case .skipped:
                input = nil
            case .operationMismatch:
                let response = ShortcutResponseBuilder.failure(
                    message: "The analyzed chat does not match this Shortcut run.",
                    errorCode: "operation_mismatch",
                    traceID: traceID
                )
                return .result(value: response.dialog)
            case .missing:
                let response = ShortcutResponseBuilder.failure(
                    message: "The analyzed chat has expired or is unavailable.",
                    errorCode: "import_not_found",
                    traceID: traceID
                )
                return .result(value: response.dialog)
            case .expired, .alreadyConsumed:
                let response = ShortcutResponseBuilder.failure(
                    message:
                        "The optional context for this analyzed chat is no longer available. Run an Analyze action again.",
                    errorCode: "input_handoff_unavailable",
                    traceID: traceID
                )
                return .result(value: response.dialog)
            case .pending:
                preconditionFailure("The readiness barrier must not return pending.")
            }
            let replyCoordinator = await MainActor.run { SuggestedRepliesCoordinator() }
            let replies = try await replyCoordinator.generate(
                chatID: analyzedChat.chatID,
                draftingInput: input,
                traceID: traceID
            )
            let response = ShortcutResponseBuilder.success(
                analyzedChat.outcome, repliesOutcome: replies)
            return .result(value: response.dialog)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SuggestedRepliesError {
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .replyGeneration, errorCode: error.code))
            let response = ShortcutResponseBuilder.success(
                analyzedChat.outcome, replyErrorCode: error.code)
            return .result(value: response.dialog)
        } catch let error as ProviderConnectionError {
            eventReporter.record(
                .importFailed(
                    traceID: traceID, stage: .replyGeneration, errorCode: error.shortcutErrorCode))
            let response = ShortcutResponseBuilder.success(
                analyzedChat.outcome, replyErrorCode: error.shortcutErrorCode
            )
            return .result(value: response.dialog)
        } catch {
            eventReporter.record(
                .importFailed(
                    traceID: traceID, stage: .replyGeneration, errorCode: "reply_generation_failed")
            )
            let response = ShortcutResponseBuilder.success(
                analyzedChat.outcome, replyErrorCode: "reply_generation_failed"
            )
            return .result(value: response.dialog)
        }
    }
}
