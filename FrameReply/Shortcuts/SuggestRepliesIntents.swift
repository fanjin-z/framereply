import AppIntents
import Combine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private nonisolated enum EndToEndShortcutSupport {
    static func transcriptItems(from values: [String]?) throws -> [String] {
        let items = (values ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !items.isEmpty else {
            throw ScreenshotImportError.noTranscript
        }
        let transcript = SharedTranscriptInput(items: items)
        guard transcript.characterCount <= SharedTranscriptInput.maximumCharacterCount,
            transcript.items.count <= SharedTranscriptInput.maximumItemCount,
            transcript.estimatedMessageCount <= SharedTranscriptInput.maximumEstimatedMessageCount
        else {
            throw ScreenshotImportError.transcriptTooLarge
        }
        return items
    }

    @MainActor
    static func finish(
        prepared: PreparedScreenshotImport,
        draftingInput: String?,
        localization: LocalizationContext
    ) async throws -> ShortcutResponsePresentation {
        let coordinator = ScreenshotImportCoordinator()
        let outcome = try coordinator.commit(prepared)

        // This flow carries one-use guidance directly into generation. Mark the
        // legacy handoff as skipped so no context is persisted for synchronization.
        let repository = ChatRepository(context: ModelContext(FrameReplyDataStore.shared))
        _ = try repository.resolveDraftingInput(
            nil,
            importID: outcome.importID,
            operationID: prepared.traceID.value
        )

        OSLogImportEventReporter().record(
            .stageStarted(traceID: prepared.traceID, stage: .replyGeneration)
        )
        do {
            let replies = try await SuggestedRepliesCoordinator().generate(
                chatID: outcome.chatID,
                draftingInput: draftingInput,
                force: true,
                localization: localization,
                traceID: prepared.traceID
            )
            return ShortcutResponseBuilder.success(
                outcome,
                repliesOutcome: replies,
                localization: localization
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SuggestedRepliesError {
            return ShortcutResponseBuilder.success(
                outcome,
                replyErrorCode: error.code,
                localization: localization
            )
        } catch let error as ProviderConnectionError {
            return ShortcutResponseBuilder.success(
                outcome,
                replyErrorCode: error.shortcutErrorCode,
                localization: localization
            )
        } catch {
            return ShortcutResponseBuilder.success(
                outcome,
                replyErrorCode: "reply_generation_failed",
                localization: localization
            )
        }
    }

    static func snippet(from response: ShortcutResponsePresentation) -> ShortcutRepliesSnippet {
        ShortcutRepliesSnippet(
            chatID: response.payload.chatID ?? "",
            chatTitle: response.payload.chatTitle
                ?? String(localized: AppStrings.Chat.importedFallback),
            importedMessageCount: response.payload.insertedMessageCount ?? 0,
            reviewRequired: response.payload.reviewRequired ?? false,
            duplicate: response.payload.duplicate ?? false,
            replies: response.payload.suggestedReplies ?? []
        )
    }

    static func conciseDialog(from response: ShortcutResponsePresentation) -> String {
        if response.payload.suggestedReplies?.count == 2 {
            return "\(response.payload.message) Two replies are ready."
        }
        return "\(response.payload.message) Replies are unavailable."
    }

    static func rethrow(_ error: Error, traceID: ImportTraceID) throws -> Never {
        if error is CancellationError {
            throw CancellationError()
        }
        if let appIntentError = error as? AppIntentError {
            throw appIntentError
        }
        if let error = error as? ChatImageIntentInputError {
            throw ShortcutExecutionError(
                message: error.localizedDescription,
                diagnosticID: traceID.diagnosticID
            )
        }
        if let error = error as? DraftingInputError {
            throw ShortcutExecutionError(
                message: error.localizedDescription,
                diagnosticID: traceID.diagnosticID
            )
        }
        if let error = error as? ScreenshotImportError {
            throw ShortcutExecutionError(
                message: error.localizedDescription,
                diagnosticID: traceID.diagnosticID
            )
        }
        if let error = error as? ProviderConnectionError {
            throw ShortcutExecutionError(
                message: error.localizedDescription,
                diagnosticID: traceID.diagnosticID
            )
        }
        if let error = error as? ShortcutExecutionError {
            throw error
        }
        throw ShortcutExecutionError(
            message: error.localizedDescription,
            diagnosticID: traceID.diagnosticID
        )
    }
}

struct SuggestRepliesFromChatImagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Suggest Replies from Chat Images"
    static let description = IntentDescription(
        "Imports chat images and generates two suggested replies in one action."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Chat Images",
        description: "One to eight images from the same chat.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var chatImages: [IntentFile]

    @Parameter(
        title: "Context or Draft",
        description: "Optional one-use direction or rough draft.",
        inputOptions: String.IntentInputOptions(multiline: true)
    )
    var draftingInput: String?

    @Parameter(
        title: "Ask for Context",
        description: "Ask whether to add context when none is supplied.",
        default: true
    )
    var askForContext: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Suggest replies from \(\.$chatImages)") {
            \.$draftingInput
            \.$askForContext
        }
    }

    func perform() async throws
        -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView
    {
        let traceID = ImportTraceID()
        let startedAt = Date()
        let lifecycleReporter = ShortcutLifecycleReporter()
        lifecycleReporter.record(
            .endToEndStarted,
            operationID: traceID.value,
            startedAt: startedAt
        )
        do {
            let images = try ChatImageIntentInput.validatedData(from: chatImages)
            let suppliedInput = try DraftingInputLimits.validated(draftingInput)
            let coordinator = await MainActor.run { ScreenshotImportCoordinator() }

            async let pendingAnalysis = coordinator.prepare(
                imageDataList: images,
                traceID: traceID
            )

            let input: String?
            if draftingInput != nil {
                input = suppliedInput
            } else if askForContext {
                let add = IntentChoiceOption(title: AppStrings.Shortcut.addContextOrDraft)
                let skip = IntentChoiceOption(title: AppStrings.Shortcut.skip)
                let choice = try await requestChoice(
                    between: [add, skip],
                    dialog: IntentDialog(AppStrings.Shortcut.imagesContextChoice)
                )
                if choice == add {
                    let requested = try await $draftingInput.requestValue(
                        IntentDialog(AppStrings.Shortcut.imagesContextPrompt)
                    )
                    input = try DraftingInputLimits.validated(requested)
                } else {
                    input = nil
                }
            } else {
                input = nil
            }

            let prepared = try await pendingAnalysis
            try Task.checkCancellation()
            let localization = LocalizationContext(locale: .current)
            let response = try await EndToEndShortcutSupport.finish(
                prepared: prepared,
                draftingInput: input,
                localization: localization
            )
            lifecycleReporter.record(
                .endToEndCompleted,
                operationID: traceID.value,
                startedAt: startedAt,
                hasInput: input != nil
            )
            return .result(
                value: response.json,
                dialog: "\(EndToEndShortcutSupport.conciseDialog(from: response))",
                view: EndToEndShortcutSupport.snippet(from: response)
            )
        } catch {
            try EndToEndShortcutSupport.rethrow(error, traceID: traceID)
        }
    }
}

struct SuggestRepliesFromChatTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Suggest Replies from Chat Text"
    static let description = IntentDescription(
        "Imports chat text and generates two suggested replies in one action."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Chat Text",
        description: "Shared text, clipboard output, or text from another action.",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var chatText: [String]

    @Parameter(
        title: "Context or Draft",
        description: "Optional one-use direction or rough draft.",
        inputOptions: String.IntentInputOptions(multiline: true)
    )
    var draftingInput: String?

    @Parameter(
        title: "Ask for Context",
        description: "Ask whether to add context when none is supplied.",
        default: true
    )
    var askForContext: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Suggest replies from \(\.$chatText)") {
            \.$draftingInput
            \.$askForContext
        }
    }

    func perform() async throws
        -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView
    {
        let traceID = ImportTraceID()
        let startedAt = Date()
        let lifecycleReporter = ShortcutLifecycleReporter()
        lifecycleReporter.record(
            .endToEndStarted,
            operationID: traceID.value,
            startedAt: startedAt
        )
        do {
            let transcriptItems = try EndToEndShortcutSupport.transcriptItems(from: chatText)
            let suppliedInput = try DraftingInputLimits.validated(draftingInput)
            let coordinator = await MainActor.run { ScreenshotImportCoordinator() }

            async let pendingAnalysis = coordinator.prepare(
                transcriptItems: transcriptItems,
                traceID: traceID
            )

            let input: String?
            if draftingInput != nil {
                input = suppliedInput
            } else if askForContext {
                let add = IntentChoiceOption(title: AppStrings.Shortcut.addContextOrDraft)
                let skip = IntentChoiceOption(title: AppStrings.Shortcut.skip)
                let choice = try await requestChoice(
                    between: [add, skip],
                    dialog: IntentDialog(AppStrings.Shortcut.textContextChoice)
                )
                if choice == add {
                    let requested = try await $draftingInput.requestValue(
                        IntentDialog(AppStrings.Shortcut.textContextPrompt)
                    )
                    input = try DraftingInputLimits.validated(requested)
                } else {
                    input = nil
                }
            } else {
                input = nil
            }

            let prepared = try await pendingAnalysis
            try Task.checkCancellation()
            let localization = LocalizationContext(locale: .current)
            let response = try await EndToEndShortcutSupport.finish(
                prepared: prepared,
                draftingInput: input,
                localization: localization
            )
            lifecycleReporter.record(
                .endToEndCompleted,
                operationID: traceID.value,
                startedAt: startedAt,
                hasInput: input != nil
            )
            return .result(
                value: response.json,
                dialog: "\(EndToEndShortcutSupport.conciseDialog(from: response))",
                view: EndToEndShortcutSupport.snippet(from: response)
            )
        } catch {
            try EndToEndShortcutSupport.rethrow(error, traceID: traceID)
        }
    }
}

struct CopyShortcutReplyIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Suggested Reply"
    static let isDiscoverable = false

    @Parameter(title: "Reply")
    var reply: String

    init() {}

    init(reply: String) {
        self.reply = reply
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            ClipboardWriter.copy(reply)
        }
        return .result(dialog: "Copied")
    }
}

@MainActor
final class ShortcutNavigationCenter: ObservableObject {
    static let shared = ShortcutNavigationCenter()

    @Published private(set) var request: Request?

    struct Request: Equatable {
        let id = UUID()
        let chatID: String
        let reviewRequired: Bool
    }

    func open(chatID: String, reviewRequired: Bool) {
        request = Request(chatID: chatID, reviewRequired: reviewRequired)
    }
}

struct OpenShortcutImportIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Imported Chat"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Chat ID")
    var chatID: String

    @Parameter(title: "Review Import")
    var reviewRequired: Bool

    init() {}

    init(chatID: String, reviewRequired: Bool) {
        self.chatID = chatID
        self.reviewRequired = reviewRequired
    }

    func perform() async throws -> some IntentResult {
        await ShortcutNavigationCenter.shared.open(
            chatID: chatID,
            reviewRequired: reviewRequired
        )
        return .result()
    }
}

struct ShortcutRepliesSnippet: View {
    let chatID: String
    let chatTitle: String
    let importedMessageCount: Int
    let reviewRequired: Bool
    let duplicate: Bool
    let replies: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chatTitle)
                .font(.headline)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(replies.prefix(2).enumerated()), id: \.offset) { index, reply in
                VStack(alignment: .leading, spacing: 8) {
                    Text(reply)
                        .font(.body)

                    Button(intent: CopyShortcutReplyIntent(reply: reply)) {
                        Label("Copy Reply \(index + 1)", systemImage: "doc.on.doc")
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }

            Button(
                intent: OpenShortcutImportIntent(
                    chatID: chatID,
                    reviewRequired: reviewRequired
                )
            ) {
                Label(
                    reviewRequired ? "Review Import" : "Open Chat",
                    systemImage: reviewRequired
                        ? "exclamationmark.bubble" : "arrow.up.forward.app"
                )
            }
        }
        .padding()
    }

    private var statusText: String {
        if duplicate {
            return "No new messages"
        }
        if reviewRequired {
            return "\(importedMessageCount) messages · Review required"
        }
        return "\(importedMessageCount) messages imported"
    }
}

struct FrameReplyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SuggestRepliesFromChatImagesIntent(),
            phrases: [
                "Suggest replies from chat images with \(.applicationName)",
                "Reply to chat images with \(.applicationName)"
            ],
            shortTitle: "Chat Image Replies",
            systemImageName: "photo.on.rectangle.angled"
        )
        AppShortcut(
            intent: SuggestRepliesFromChatTextIntent(),
            phrases: [
                "Suggest replies from chat text with \(.applicationName)",
                "Reply to chat text with \(.applicationName)"
            ],
            shortTitle: "Chat Text Replies",
            systemImageName: "text.bubble"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .purple
}
