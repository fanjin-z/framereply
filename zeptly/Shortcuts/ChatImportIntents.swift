//
//  ChatImportIntents.swift
//  zeptly
//
//  Created by GitHub Copilot.
//

import AppIntents
import Foundation
import SwiftData
import UniformTypeIdentifiers

nonisolated struct AnalyzedChatEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Analyzed Chat")
    static let defaultQuery = AnalyzedChatEntityQuery()

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
        DisplayRepresentation(title: "\(chatName)", subtitle: "Analyzed chat input")
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
        matchedExisting = record.matchedExisting
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

nonisolated struct AnalyzedChatEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AnalyzedChatEntity] {
        try await MainActor.run {
            let repository = ChatRepository(context: ModelContext(ZeptlyDataStore.shared))
            return try identifiers.compactMap { identifier in
                guard let record = try repository.importRecord(id: identifier),
                    let chat = try repository.chat(id: record.chatID)
                else {
                    return nil
                }
                return AnalyzedChatEntity(
                    record: record, chatName: chat.name, operationID: record.operationID)
            }
        }
    }
}

nonisolated enum ChatImportIntentSupport {
    static func finalize(
        outcome: ScreenshotImportOutcome,
        input: String?,
        traceID: ImportTraceID,
        startedAt: Date,
        eventReporter: any ImportEventReporting,
        lifecycleReporter: ShortcutLifecycleReporter
    ) async throws -> AnalyzedChatEntity {
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
        lifecycleReporter.record(
            .analyzeReturned,
            operationID: traceID.value,
            startedAt: startedAt
        )
        return AnalyzedChatEntity(outcome: outcome, operationID: traceID.value)
    }

    static func rethrowImportError(
        _ error: Error,
        traceID: ImportTraceID,
        startedAt: Date,
        eventReporter: any ImportEventReporting,
        lifecycleReporter: ShortcutLifecycleReporter,
        synchronizationMessage: String,
        persistenceMessage: String
    ) throws -> Never {
        if error is CancellationError {
            lifecycleReporter.record(
                .inputCancelled,
                operationID: traceID.value,
                startedAt: startedAt
            )
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .shortcut, errorCode: "cancelled")
            )
            throw CancellationError()
        }
        if let appIntentError = error as? AppIntentError {
            lifecycleReporter.record(
                .inputCancelled,
                operationID: traceID.value,
                startedAt: startedAt
            )
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .shortcut, errorCode: "cancelled")
            )
            throw appIntentError
        }
        if let importError = error as? ScreenshotImportError {
            throw ShortcutExecutionError(
                message: importError.localizedDescription,
                diagnosticID: traceID.diagnosticID
            )
        }
        if let providerError = error as? ProviderConnectionError {
            throw ShortcutExecutionError(
                message: providerError.localizedDescription,
                diagnosticID: traceID.diagnosticID
            )
        }
        if error is DraftingInputSynchronizationError {
            eventReporter.record(
                .importFailed(
                    traceID: traceID,
                    stage: .persistence,
                    errorCode: "input_synchronization_failed"
                )
            )
            throw ShortcutExecutionError(
                message: synchronizationMessage,
                diagnosticID: traceID.diagnosticID
            )
        }
        if let shortcutError = error as? ShortcutExecutionError {
            throw shortcutError
        }

        eventReporter.record(
            .importFailed(traceID: traceID, stage: .persistence, errorCode: "import_failed")
        )
        throw ShortcutExecutionError(
            message: persistenceMessage,
            diagnosticID: traceID.diagnosticID
        )
    }
}

nonisolated struct ShortcutExecutionError: LocalizedError, CustomLocalizedStringResourceConvertible,
    Sendable
{
    let message: String
    let diagnosticID: String

    var errorDescription: String? { "\(message) Reference \(diagnosticID)." }
    var localizedStringResource: LocalizedStringResource {
        "\(message) Reference \(diagnosticID)."
    }
}

nonisolated enum ChatImageIntentInputError: LocalizedError, Equatable, Sendable {
    case noImages
    case tooManyImages(maximum: Int)
    case invalidImage(position: Int)

    var errorDescription: String? {
        switch self {
        case .noImages:
            "No chat images were provided."
        case .tooManyImages(let maximum):
            "Choose no more than \(maximum) images from the same chat."
        case .invalidImage(let position):
            "Image \(position) is empty or is not a readable image."
        }
    }

    var code: String {
        switch self {
        case .noImages:
            "no_image"
        case .tooManyImages:
            "too_many_images"
        case .invalidImage:
            "invalid_image"
        }
    }
}

nonisolated enum ChatImageIntentInput {
    static let maximumImageCount = 8

    static func validatedData(from files: [IntentFile]?) throws -> [Data] {
        let files = files ?? []
        guard !files.isEmpty else {
            throw ChatImageIntentInputError.noImages
        }
        guard files.count <= maximumImageCount else {
            throw ChatImageIntentInputError.tooManyImages(maximum: maximumImageCount)
        }

        return try files.enumerated().map { index, file in
            let data = file.data
            guard !data.isEmpty,
                ChatScreenshotImageInput.isSupportedImage(
                    data: data,
                    filename: file.filename,
                    type: file.type
                )
            else {
                throw ChatImageIntentInputError.invalidImage(position: index + 1)
            }
            return data
        }
    }
}

struct AnalyzeChatImagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Analyze Chat Images"
    static let description = IntentDescription(
        "Imports one to eight images from the same chat while you optionally add context or draft a reply. The images aren't saved."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Chat Images",
        description:
            "Pass one to eight images from the same chat, such as shared photos or the output from Take Screenshot.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var chatImages: [IntentFile]?

    @Parameter(
        title: "Context or Draft",
        description: "Optional context or a rough reply used once for this generation.",
        inputOptions: String.IntentInputOptions(multiline: true)
    )
    var draftingInput: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Analyze \(\.$chatImages)") {
            \.$draftingInput
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<AnalyzedChatEntity> {
        let traceID = ImportTraceID()
        let startedAt = Date()
        let eventReporter = OSLogImportEventReporter()
        let lifecycleReporter = ShortcutLifecycleReporter()

        let imageDataList: [Data]
        do {
            imageDataList = try ChatImageIntentInput.validatedData(from: chatImages)
        } catch let error as ChatImageIntentInputError {
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .shortcut, errorCode: error.code)
            )
            throw ShortcutExecutionError(
                message: error.localizedDescription,
                diagnosticID: traceID.diagnosticID
            )
        }

        eventReporter.record(.stageStarted(traceID: traceID, stage: .screenshotDecoding))
        let coordinator = await MainActor.run { ScreenshotImportCoordinator() }
        do {
            lifecycleReporter.record(
                .analysisStarted, operationID: traceID.value, startedAt: startedAt)
            async let pendingOutcome: ScreenshotImportOutcome = {
                let outcome = try await coordinator.process(
                    imageDataList: imageDataList,
                    traceID: traceID
                )
                lifecycleReporter.record(
                    .analysisCompleted, operationID: traceID.value, startedAt: startedAt)
                return outcome
            }()

            let input: String?
            if let draftingInput {
                input = draftingInput
            } else if #available(iOS 26.0, *) {
                lifecycleReporter.record(
                    .inputChoiceDisplayed, operationID: traceID.value, startedAt: startedAt)
                let add = IntentChoiceOption(title: "Add Context or Draft")
                let skip = IntentChoiceOption(title: "Skip")
                let choice = try await requestChoice(
                    between: [add, skip],
                    dialog:
                        "Add optional context or a rough draft while Zeptly analyzes the chat images?"
                )
                if choice == skip {
                    input = nil
                } else {
                    lifecycleReporter.record(
                        .inputPromptDisplayed, operationID: traceID.value, startedAt: startedAt)
                    input = try await $draftingInput.requestValue(
                        "Analyzing chat images… Add context or draft what you want to say. Tap Done when finished. Cancel stops the shortcut."
                    )
                }
            } else {
                lifecycleReporter.record(
                    .inputPromptDisplayed, operationID: traceID.value, startedAt: startedAt)
                input = try await $draftingInput.requestValue(
                    "Analyzing chat images… Add optional context or a draft. Tap Done empty to skip; Cancel stops the shortcut."
                )
            }

            let entity = try await ChatImportIntentSupport.finalize(
                outcome: try await pendingOutcome,
                input: input,
                traceID: traceID,
                startedAt: startedAt,
                eventReporter: eventReporter,
                lifecycleReporter: lifecycleReporter
            )
            return .result(value: entity)
        } catch {
            try ChatImportIntentSupport.rethrowImportError(
                error,
                traceID: traceID,
                startedAt: startedAt,
                eventReporter: eventReporter,
                lifecycleReporter: lifecycleReporter,
                synchronizationMessage:
                    "The optional input could not be synchronized with this image import.",
                persistenceMessage: "The chat history could not be saved."
            )
        }
    }
}

struct AnalyzeCopiedMessagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Analyze Chat Text"
    static let description = IntentDescription(
        "Imports shared or copied chat text while you optionally add context or draft a reply. The raw text isn't saved."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Chat Text",
        description: "Pass shared plain text, Get Clipboard output, or text from another action.",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var copiedMessages: [String]?

    @Parameter(
        title: "Context or Draft",
        description: "Optional context or a rough reply used once for this generation.",
        inputOptions: String.IntentInputOptions(multiline: true)
    )
    var draftingInput: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Analyze \(\.$copiedMessages)") {
            \.$draftingInput
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<AnalyzedChatEntity> {
        let traceID = ImportTraceID()
        let startedAt = Date()
        let eventReporter = OSLogImportEventReporter()
        let lifecycleReporter = ShortcutLifecycleReporter()
        let transcriptItems = (copiedMessages ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !transcriptItems.isEmpty else {
            eventReporter.record(
                .importFailed(traceID: traceID, stage: .shortcut, errorCode: "no_transcript")
            )
            throw ShortcutExecutionError(
                message: "No shared or copied message text was provided.",
                diagnosticID: traceID.diagnosticID
            )
        }

        let coordinator = await MainActor.run { ScreenshotImportCoordinator() }
        do {
            lifecycleReporter.record(
                .analysisStarted, operationID: traceID.value, startedAt: startedAt)
            async let pendingOutcome: ScreenshotImportOutcome = {
                let outcome = try await coordinator.process(
                    transcriptItems: transcriptItems,
                    traceID: traceID
                )
                lifecycleReporter.record(
                    .analysisCompleted, operationID: traceID.value, startedAt: startedAt)
                return outcome
            }()

            let input: String?
            if let draftingInput {
                input = draftingInput
            } else if #available(iOS 26.0, *) {
                lifecycleReporter.record(
                    .inputChoiceDisplayed, operationID: traceID.value, startedAt: startedAt)
                let add = IntentChoiceOption(title: "Add Context or Draft")
                let skip = IntentChoiceOption(title: "Skip")
                let choice = try await requestChoice(
                    between: [add, skip],
                    dialog:
                        "Add optional context or a rough draft while Zeptly analyzes the chat text?"
                )
                if choice == skip {
                    input = nil
                } else {
                    lifecycleReporter.record(
                        .inputPromptDisplayed, operationID: traceID.value, startedAt: startedAt)
                    input = try await $draftingInput.requestValue(
                        "Analyzing chat text… Add context or draft what you want to say. Tap Done when finished."
                    )
                }
            } else {
                lifecycleReporter.record(
                    .inputPromptDisplayed, operationID: traceID.value, startedAt: startedAt)
                input = try await $draftingInput.requestValue(
                    "Analyzing chat text… Add optional context or a draft. Tap Done empty to skip."
                )
            }

            let entity = try await ChatImportIntentSupport.finalize(
                outcome: try await pendingOutcome,
                input: input,
                traceID: traceID,
                startedAt: startedAt,
                eventReporter: eventReporter,
                lifecycleReporter: lifecycleReporter
            )
            return .result(value: entity)
        } catch {
            try ChatImportIntentSupport.rethrowImportError(
                error,
                traceID: traceID,
                startedAt: startedAt,
                eventReporter: eventReporter,
                lifecycleReporter: lifecycleReporter,
                synchronizationMessage:
                    "The optional input could not be synchronized with this chat import.",
                persistenceMessage: "The imported chat text could not be saved."
            )
        }
    }
}
