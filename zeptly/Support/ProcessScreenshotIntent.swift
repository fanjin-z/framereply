//
//  ProcessScreenshotIntent.swift
//  zeptly
//
//  Created by GitHub Copilot.
//

import AppIntents
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

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
        let replyStatus = repliesOutcome.map {
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
                replyErrorCode: repliesOutcome == nil ? (replyErrorCode ?? "reply_generation_failed") : nil
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

nonisolated struct ScreenshotImportEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Screenshot Import")
    static let defaultQuery = ScreenshotImportEntityQuery()

    let id: UUID
    let operationID: UUID
    let chatID: String
    let chatName: String
    let diagnosticID: String
    let matchedExisting: Bool
    let reviewRequired: Bool
    let duplicate: Bool
    let insertedMessageCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(chatName)", subtitle: "Analyzed chat screenshot")
    }

    init(outcome: ScreenshotImportOutcome, operationID: UUID) {
        id = outcome.importID
        self.operationID = operationID
        chatID = outcome.chatID
        chatName = outcome.chatName
        diagnosticID = outcome.diagnosticID
        matchedExisting = outcome.matchedExisting
        reviewRequired = outcome.reviewRequired
        duplicate = outcome.duplicate
        insertedMessageCount = outcome.insertedMessageCount
    }

    init(record: ChatImportRecord, chatName: String, operationID: UUID) {
        id = record.id
        self.operationID = operationID
        chatID = record.chatID
        self.chatName = chatName
        diagnosticID = record.diagnosticID ?? "UNKNOWN"
        matchedExisting = record.matchedExisting ?? false
        reviewRequired = record.requiresReview
        duplicate = record.isDuplicate
        insertedMessageCount = record.insertedMessageCount
    }

    var outcome: ScreenshotImportOutcome {
        ScreenshotImportOutcome(
            chatID: chatID,
            chatName: chatName,
            importID: id,
            diagnosticID: diagnosticID,
            matchedExisting: matchedExisting,
            reviewRequired: reviewRequired,
            duplicate: duplicate,
            insertedMessageCount: insertedMessageCount
        )
    }
}

nonisolated struct ScreenshotImportEntityQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [UUID]) async throws -> [ScreenshotImportEntity] {
        try await MainActor.run {
            let repository = ChatRepository(context: ModelContext(ZeptlyDataStore.shared))
            return try identifiers.compactMap { identifier in
                guard let record = try repository.importRecord(id: identifier),
                    let operationID = record.operationID,
                    let chat = try repository.chat(id: record.chatID)
                else {
                    return nil
                }
                return ScreenshotImportEntity(record: record, chatName: chat.name, operationID: operationID)
            }
        }
    }
}

nonisolated struct ShortcutExecutionError: LocalizedError, CustomLocalizedStringResourceConvertible, Sendable {
    let message: String
    let diagnosticID: String

    var errorDescription: String? { "\(message) Reference \(diagnosticID)." }
    var localizedStringResource: LocalizedStringResource {
        "\(message) Reference \(diagnosticID)."
    }
}

struct AnalyzeChatScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Analyze Chat Screenshot"
    static let description = IntentDescription(
        "Imports visible messages while you optionally add context or draft a reply. The screenshot isn't saved.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Screenshot",
        description: "Pass an image, such as the output from Take Screenshot or Get Clipboard.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile?

    @Parameter(
        title: "Context or Draft",
        description: "Optional context or a rough reply used once for this generation.",
        inputOptions: String.IntentInputOptions(multiline: true)
    )
    var draftingInput: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Analyze \(\.$screenshot)") {
            \.$draftingInput
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<ScreenshotImportEntity> {
        let traceID = ImportTraceID()
        let startedAt = Date()
        let eventReporter = OSLogImportEventReporter()
        let lifecycleReporter = ShortcutLifecycleReporter()
        guard let screenshot else {
            eventReporter.record(.importFailed(traceID: traceID, stage: .shortcut, errorCode: "no_image"))
            throw ShortcutExecutionError(
                message: "No image input was provided.", diagnosticID: traceID.diagnosticID
            )
        }

        eventReporter.record(.stageStarted(traceID: traceID, stage: .screenshotDecoding))
        guard isImageFile(screenshot) else {
            eventReporter.record(.importFailed(traceID: traceID, stage: .screenshotDecoding, errorCode: "invalid_image"))
            throw ShortcutExecutionError(
                message: "The provided file is not a readable image.", diagnosticID: traceID.diagnosticID
            )
        }

        let coordinator = await MainActor.run { ScreenshotImportCoordinator() }
        do {
            lifecycleReporter.record(.analysisStarted, operationID: traceID.value, startedAt: startedAt)
            async let pendingOutcome: ScreenshotImportOutcome = {
                let outcome = try await coordinator.process(
                    imageData: screenshot.data,
                    traceID: traceID
                )
                lifecycleReporter.record(.analysisCompleted, operationID: traceID.value, startedAt: startedAt)
                return outcome
            }()

            let input: String?
            if let draftingInput {
                input = draftingInput
            } else if #available(iOS 26.0, *) {
                lifecycleReporter.record(.inputChoiceDisplayed, operationID: traceID.value, startedAt: startedAt)
                let add = IntentChoiceOption(title: "Add Context or Draft")
                let skip = IntentChoiceOption(title: "Skip")
                let choice = try await requestChoice(
                    between: [add, skip],
                    dialog: "Add optional context or a rough draft while Zeptly analyzes the screenshot?"
                )
                if choice == skip {
                    input = nil
                } else {
                    lifecycleReporter.record(.inputPromptDisplayed, operationID: traceID.value, startedAt: startedAt)
                    input = try await $draftingInput.requestValue(
                        "Analyzing screenshot… Add context or draft what you want to say. Tap Done when finished. Cancel stops the shortcut."
                    )
                }
            } else {
                lifecycleReporter.record(.inputPromptDisplayed, operationID: traceID.value, startedAt: startedAt)
                input = try await $draftingInput.requestValue(
                    "Analyzing screenshot… Add optional context or a draft. Tap Done empty to skip; Cancel stops the shortcut."
                )
            }

            let outcome = try await pendingOutcome
            eventReporter.record(.stageStarted(traceID: traceID, stage: .persistence))
            let state = try await MainActor.run {
                let repository = ChatRepository(context: ModelContext(ZeptlyDataStore.shared))
                return try repository.resolveDraftingInput(
                    input,
                    importID: outcome.importID,
                    operationID: traceID.value
                )
            }
            let hasInput = state == .submitted
            lifecycleReporter.record(
                hasInput ? .inputSubmitted : .inputSkipped,
                operationID: traceID.value,
                startedAt: startedAt,
                state: state,
                hasInput: hasInput
            )
            lifecycleReporter.record(
                .stateCommitted,
                operationID: traceID.value,
                startedAt: startedAt,
                state: state,
                hasInput: hasInput
            )
            lifecycleReporter.record(.analyzeReturned, operationID: traceID.value, startedAt: startedAt)
            return .result(value: ScreenshotImportEntity(outcome: outcome, operationID: traceID.value))
        } catch is CancellationError {
            lifecycleReporter.record(.inputCancelled, operationID: traceID.value, startedAt: startedAt)
            eventReporter.record(.importFailed(traceID: traceID, stage: .shortcut, errorCode: "cancelled"))
            throw CancellationError()
        } catch let error as AppIntentError {
            lifecycleReporter.record(.inputCancelled, operationID: traceID.value, startedAt: startedAt)
            eventReporter.record(.importFailed(traceID: traceID, stage: .shortcut, errorCode: "cancelled"))
            throw error
        } catch let error as ScreenshotImportError {
            throw ShortcutExecutionError(
                message: error.localizedDescription, diagnosticID: traceID.diagnosticID
            )
        } catch let error as ProviderConnectionError {
            throw ShortcutExecutionError(
                message: error.localizedDescription, diagnosticID: traceID.diagnosticID
            )
        } catch is DraftingInputSynchronizationError {
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .persistence, errorCode: "input_synchronization_failed")
            )
            throw ShortcutExecutionError(
                message: "The optional input could not be synchronized with this screenshot import.",
                diagnosticID: traceID.diagnosticID
            )
        } catch let error as ShortcutExecutionError {
            throw error
        } catch {
            eventReporter.record(.importFailed(traceID: traceID, stage: .persistence, errorCode: "import_failed"))
            throw ShortcutExecutionError(
                message: "The chat history could not be saved.", diagnosticID: traceID.diagnosticID
            )
        }
    }

    private func isImageFile(_ file: IntentFile) -> Bool {
        if let type = file.type {
            return type.conforms(to: .image)
        }

        let fileExtension = URL(fileURLWithPath: file.filename).pathExtension.lowercased()
        if !fileExtension.isEmpty,
            let inferredType = UTType(filenameExtension: fileExtension),
            inferredType.conforms(to: .image)
        {
            return true
        }

        guard let source = CGImageSourceCreateWithData(file.data as CFData, nil) else {
            return false
        }

        if let typeIdentifier = CGImageSourceGetType(source) as String?,
            let sourceType = UTType(typeIdentifier),
            sourceType.conforms(to: .image)
        {
            return true
        }

        if CGImageSourceGetCount(source) > 0 {
            return true
        }

        return !file.data.isEmpty
    }
}

struct GenerateSuggestedRepliesIntent: AppIntent {
    static let title: LocalizedStringResource = "Generate Suggested Replies"
    static let description = IntentDescription(
        "Generates two replies for a chat screenshot analyzed by Zeptly.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Analyzed Chat",
        description: "The output from Analyze Chat Screenshot.",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var preparedChat: ScreenshotImportEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Generate replies for \(\.$preparedChat)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let fallbackTraceID = ImportTraceID()
        guard let preparedChat else {
            let response = ShortcutResponseBuilder.failure(
                message: "No analyzed chat was provided.",
                errorCode: "no_prepared_chat",
                traceID: fallbackTraceID
            )
            return .result(value: response.dialog)
        }

        let eventReporter = OSLogImportEventReporter()
        let traceID = ImportTraceID(value: preparedChat.operationID)
        let startedAt = Date()
        let lifecycleReporter = ShortcutLifecycleReporter()
        lifecycleReporter.record(.generateStarted, operationID: preparedChat.operationID, startedAt: startedAt)
        eventReporter.record(.stageStarted(traceID: traceID, stage: .replyGeneration))
        do {
            let consumption = try await DraftingInputBarrier.waitUntilReady {
                let result = try await MainActor.run {
                    let repository = ChatRepository(context: ModelContext(ZeptlyDataStore.shared))
                    guard let record = try repository.importRecord(id: preparedChat.id),
                        record.chatID == preparedChat.chatID
                    else {
                        return DraftingInputConsumption.missing
                    }
                    return try repository.consumeDraftingInputIfReady(
                        importID: preparedChat.id,
                        operationID: preparedChat.operationID
                    )
                }
                let state: DraftingInputState? = switch result {
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
                    operationID: preparedChat.operationID,
                    startedAt: startedAt,
                    state: state,
                    hasInput: hasInput
                )
                return result
            }

            let input: String?
            switch consumption {
            case let .submitted(value):
                input = value
                lifecycleReporter.record(
                    .contextConsumed,
                    operationID: preparedChat.operationID,
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
                    message: "The optional context for this analyzed chat is no longer available. Run Analyze Chat Screenshot again.",
                    errorCode: "input_handoff_unavailable",
                    traceID: traceID
                )
                return .result(value: response.dialog)
            case .pending:
                preconditionFailure("The readiness barrier must not return pending.")
            }
            let replyCoordinator = await MainActor.run { SuggestedRepliesCoordinator() }
            let replies = try await replyCoordinator.generate(
                chatID: preparedChat.chatID,
                draftingInput: input,
                traceID: traceID
            )
            let response = ShortcutResponseBuilder.success(preparedChat.outcome, repliesOutcome: replies)
            return .result(value: response.dialog)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SuggestedRepliesError {
            eventReporter.record(.importFailed(traceID: traceID, stage: .replyGeneration, errorCode: error.code))
            let response = ShortcutResponseBuilder.success(preparedChat.outcome, replyErrorCode: error.code)
            return .result(value: response.dialog)
        } catch let error as ProviderConnectionError {
            eventReporter.record(.importFailed(traceID: traceID, stage: .replyGeneration, errorCode: error.shortcutErrorCode))
            let response = ShortcutResponseBuilder.success(
                preparedChat.outcome, replyErrorCode: error.shortcutErrorCode
            )
            return .result(value: response.dialog)
        } catch {
            eventReporter.record(.importFailed(traceID: traceID, stage: .replyGeneration, errorCode: "reply_generation_failed"))
            let response = ShortcutResponseBuilder.success(
                preparedChat.outcome, replyErrorCode: "reply_generation_failed"
            )
            return .result(value: response.dialog)
        }
    }
}

struct ZeptlyShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AnalyzeChatScreenshotIntent(),
            phrases: [
                "Analyze chat screenshot in \(.applicationName)",
                "Analyze my chat screenshot with \(.applicationName)"
            ],
            shortTitle: "Analyze Chat Screenshot",
            systemImageName: "photo.on.rectangle.angled"
        )
        AppShortcut(
            intent: GenerateSuggestedRepliesIntent(),
            phrases: ["Generate suggested replies with \(.applicationName)"],
            shortTitle: "Generate Suggested Replies",
            systemImageName: "text.bubble"
        )
    }
}
