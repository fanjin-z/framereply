import AppIntents
import Combine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum ShortcutReplyChoiceBuilder {
    static func values(from replies: [String]?) -> [String] {
        Array(
            (replies ?? [])
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(2)
        )
    }

    static func values(from response: ShortcutResponsePresentation) -> [String] {
        values(from: response.payload.suggestedReplies)
    }
}

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

    static func runImages(
        _ chatImages: [IntentFile],
        draftingInput: String?,
        traceID: ImportTraceID,
        resolveDraftingInput: (String?) async throws -> String?
    ) async throws -> ShortcutResponsePresentation {
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
            let coordinator = await MainActor.run {
                AppIntentDependencies.screenshotImportCoordinator()
            }

            async let pendingAnalysis = coordinator.prepare(
                imageDataList: images,
                traceID: traceID
            )
            let input = try await resolveDraftingInput(suppliedInput)
            let prepared = try await pendingAnalysis
            try Task.checkCancellation()

            let response = try await finish(
                prepared: prepared,
                draftingInput: input,
                localization: LocalizationContext(locale: .current)
            )
            lifecycleReporter.record(
                .endToEndCompleted,
                operationID: traceID.value,
                startedAt: startedAt,
                hasInput: input != nil
            )
            return response
        } catch {
            try rethrow(error, traceID: traceID)
        }
    }

    static func runText(
        _ chatText: [String],
        draftingInput: String?,
        traceID: ImportTraceID,
        resolveDraftingInput: (String?) async throws -> String?
    ) async throws -> ShortcutResponsePresentation {
        let startedAt = Date()
        let lifecycleReporter = ShortcutLifecycleReporter()
        lifecycleReporter.record(
            .endToEndStarted,
            operationID: traceID.value,
            startedAt: startedAt
        )

        do {
            let transcriptItems = try transcriptItems(from: chatText)
            let suppliedInput = try DraftingInputLimits.validated(draftingInput)
            let coordinator = await MainActor.run {
                AppIntentDependencies.screenshotImportCoordinator()
            }

            async let pendingAnalysis = coordinator.prepare(
                transcriptItems: transcriptItems,
                traceID: traceID
            )
            let input = try await resolveDraftingInput(suppliedInput)
            let prepared = try await pendingAnalysis
            try Task.checkCancellation()

            let response = try await finish(
                prepared: prepared,
                draftingInput: input,
                localization: LocalizationContext(locale: .current)
            )
            lifecycleReporter.record(
                .endToEndCompleted,
                operationID: traceID.value,
                startedAt: startedAt,
                hasInput: input != nil
            )
            return response
        } catch {
            try rethrow(error, traceID: traceID)
        }
    }

    @MainActor
    static func finish(
        prepared: PreparedScreenshotImport,
        draftingInput: String?,
        localization: LocalizationContext
    ) async throws -> ShortcutResponsePresentation {
        let coordinator = AppIntentDependencies.screenshotImportCoordinator()
        let outcome = try coordinator.commit(prepared)

        // This flow carries one-use guidance directly into generation. Mark the
        // legacy handoff as skipped so no context is persisted for synchronization.
        let repository = AppIntentDependencies.chatRepository()
        _ = try repository.resolveDraftingInput(
            nil,
            importID: outcome.importID,
            operationID: prepared.traceID.value
        )

        OSLogImportEventReporter().record(
            .stageStarted(traceID: prepared.traceID, stage: .replyGeneration)
        )
        do {
            let replies = try await AppIntentDependencies.suggestedRepliesCoordinator().generate(
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

private protocol ShortcutReplyConfirmingIntent: AppIntent {}

extension ShortcutReplyConfirmingIntent {
    func confirmReply(
        from response: ShortcutResponsePresentation
    ) async throws -> String {
        let replies = ShortcutReplyChoiceBuilder.values(from: response)
        if replies.isEmpty,
            response.payload.replyStatus != .failed,
            response.payload.suggestedReplies?.isEmpty == true
        {
            return response.dialog
        }
        guard !replies.isEmpty else {
            throw ShortcutExecutionError(
                message: String(
                    localized: "Replies are unavailable. Open FrameReply to try again."
                ),
                diagnosticID: response.payload.diagnosticID
            )
        }

        let sessionID = UUID().uuidString
        let snippetIntent = ShortcutRepliesConfirmationSnippetIntent(
            selectionSessionID: sessionID,
            chatID: response.payload.chatID ?? "",
            chatTitle: response.payload.chatTitle
                ?? String(localized: AppStrings.Chat.importedFallback),
            importedMessageCount: response.payload.insertedMessageCount ?? 0,
            reviewRequired: response.payload.reviewRequired ?? false,
            duplicate: response.payload.duplicate ?? false,
            replies: replies
        )
        ShortcutReplySelectionStore.shared.begin(sessionID: sessionID)

        do {
            let reply = try await requestConfirmation(
                actionName: .custom(
                    acceptLabel: "Use Reply",
                    acceptAlternatives: [],
                    denyLabel: "Cancel",
                    denyAlternatives: []
                ),
                dialog: IntentDialog(
                    full: "Choose a suggested reply.",
                    supporting: ""
                ),
                showDialogAsPrompt: false,
                snippetIntent: snippetIntent
            )
            ShortcutReplySelectionStore.shared.end(sessionID: sessionID)
            return reply
        } catch {
            ShortcutReplySelectionStore.shared.end(sessionID: sessionID)
            throw error
        }
    }
}

struct SuggestRepliesFromChatImagesIntent: ShortcutReplyConfirmingIntent {
    static let title: LocalizedStringResource = "Suggest Replies from Chat Images"
    static let description = IntentDescription(
        "Imports chat images, suggests replies, and returns the one you choose."
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
        title: "Reply Guidance",
        description: "One-use context, direction, tone, or a rough draft for the next replies.",
        inputOptions: String.IntentInputOptions(multiline: true)
    )
    var draftingInput: String?

    @Parameter(
        title: "Ask for Reply Guidance",
        description: "Ask whether to add reply guidance when none is supplied.",
        default: true
    )
    var askForContext: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Suggest replies from \(\.$chatImages)") {
            \.$draftingInput
            \.$askForContext
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let traceID = ImportTraceID()
        let response = try await EndToEndShortcutSupport.runImages(
            chatImages,
            draftingInput: draftingInput,
            traceID: traceID
        ) { suppliedInput in
            if draftingInput != nil {
                return suppliedInput
            } else if askForContext {
                let add = IntentChoiceOption(title: AppStrings.Shortcut.addReplyGuidance)
                let skip = IntentChoiceOption(title: AppStrings.Shortcut.skip)
                let choice = try await requestChoice(
                    between: [add, skip],
                    dialog: IntentDialog(AppStrings.Shortcut.imagesReplyGuidanceChoice)
                )
                if choice == add {
                    let requested = try await $draftingInput.requestValue(
                        IntentDialog(AppStrings.Shortcut.imagesReplyGuidancePrompt)
                    )
                    return try DraftingInputLimits.validated(requested)
                }
                return nil
            }
            return nil
        }
        return .result(value: try await confirmReply(from: response))
    }
}

struct SuggestRepliesFromChatTextIntent: ShortcutReplyConfirmingIntent {
    static let title: LocalizedStringResource = "Suggest Replies from Chat Text"
    static let description = IntentDescription(
        "Imports chat text, suggests replies, and returns the one you choose."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Chat Text",
        description: "Shared text, clipboard output, or text from another action.",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var chatText: [String]

    @Parameter(
        title: "Reply Guidance",
        description: "One-use context, direction, tone, or a rough draft for the next replies.",
        inputOptions: String.IntentInputOptions(multiline: true)
    )
    var draftingInput: String?

    @Parameter(
        title: "Ask for Reply Guidance",
        description: "Ask whether to add reply guidance when none is supplied.",
        default: true
    )
    var askForContext: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Suggest replies from \(\.$chatText)") {
            \.$draftingInput
            \.$askForContext
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let traceID = ImportTraceID()
        let response = try await EndToEndShortcutSupport.runText(
            chatText,
            draftingInput: draftingInput,
            traceID: traceID
        ) { suppliedInput in
            if draftingInput != nil {
                return suppliedInput
            } else if askForContext {
                let add = IntentChoiceOption(title: AppStrings.Shortcut.addReplyGuidance)
                let skip = IntentChoiceOption(title: AppStrings.Shortcut.skip)
                let choice = try await requestChoice(
                    between: [add, skip],
                    dialog: IntentDialog(AppStrings.Shortcut.textReplyGuidanceChoice)
                )
                if choice == add {
                    let requested = try await $draftingInput.requestValue(
                        IntentDialog(AppStrings.Shortcut.textReplyGuidancePrompt)
                    )
                    return try DraftingInputLimits.validated(requested)
                }
                return nil
            }
            return nil
        }
        return .result(value: try await confirmReply(from: response))
    }
}

@MainActor
final class ShortcutReplySelectionStore {
    static let shared = ShortcutReplySelectionStore()

    private var selectedReplyIndices: [String: Int] = [:]

    func begin(sessionID: String) {
        selectedReplyIndices[sessionID] = 0
    }

    func select(replyIndex: Int, sessionID: String) {
        selectedReplyIndices[sessionID] = max(0, replyIndex)
    }

    func selectedReplyIndex(sessionID: String, replyCount: Int) -> Int {
        guard replyCount > 0 else {
            return 0
        }
        return min(selectedReplyIndices[sessionID] ?? 0, replyCount - 1)
    }

    func end(sessionID: String) {
        selectedReplyIndices.removeValue(forKey: sessionID)
    }

    func reset() {
        selectedReplyIndices.removeAll()
    }
}

struct SelectShortcutReplyIntent: AppIntent {
    static let title: LocalizedStringResource = "Select Suggested Reply"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "Selection Session ID")
    var selectionSessionID: String

    @Parameter(title: "Reply Number")
    var replyIndex: Int

    init() {}

    init(selectionSessionID: String, replyIndex: Int) {
        self.selectionSessionID = selectionSessionID
        self.replyIndex = replyIndex
    }

    func perform() async throws -> some IntentResult {
        await ShortcutReplySelectionStore.shared.select(
            replyIndex: replyIndex,
            sessionID: selectionSessionID
        )
        return .result()
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

struct ShortcutRepliesConfirmationSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Choose Suggested Reply"
    static let isDiscoverable = false

    @Parameter(title: "Selection Session ID")
    var selectionSessionID: String

    @Parameter(title: "Chat ID")
    var chatID: String

    @Parameter(title: "Chat Title")
    var chatTitle: String

    @Parameter(title: "Imported Message Count")
    var importedMessageCount: Int

    @Parameter(title: "Review Required")
    var reviewRequired: Bool

    @Parameter(title: "Duplicate Import")
    var duplicate: Bool

    @Parameter(title: "Replies")
    var replies: [String]

    init() {}

    init(
        selectionSessionID: String,
        chatID: String,
        chatTitle: String,
        importedMessageCount: Int,
        reviewRequired: Bool,
        duplicate: Bool,
        replies: [String]
    ) {
        self.selectionSessionID = selectionSessionID
        self.chatID = chatID
        self.chatTitle = chatTitle
        self.importedMessageCount = importedMessageCount
        self.reviewRequired = reviewRequired
        self.duplicate = duplicate
        self.replies = replies
    }

    @MainActor
    func perform() async throws
        -> some IntentResult & ReturnsValue<String> & ShowsSnippetView
    {
        let visibleReplies = ShortcutReplyChoiceBuilder.values(from: replies)
        let selectedReplyIndex = ShortcutReplySelectionStore.shared.selectedReplyIndex(
            sessionID: selectionSessionID,
            replyCount: visibleReplies.count
        )
        let selectedReply =
            visibleReplies.indices.contains(selectedReplyIndex)
            ? visibleReplies[selectedReplyIndex] : ""

        return .result(
            value: selectedReply,
            view: ShortcutRepliesSnippet(
                chatID: chatID,
                chatTitle: chatTitle,
                importedMessageCount: importedMessageCount,
                reviewRequired: reviewRequired,
                duplicate: duplicate,
                replies: visibleReplies,
                selectionSessionID: selectionSessionID,
                selectedReplyIndex: selectedReplyIndex
            )
        )
    }
}

struct ShortcutRepliesSnippet: View {
    let chatID: String
    let chatTitle: String
    let importedMessageCount: Int
    let reviewRequired: Bool
    let duplicate: Bool
    let replies: [String]
    let selectionSessionID: String?
    let selectedReplyIndex: Int?

    init(
        chatID: String,
        chatTitle: String,
        importedMessageCount: Int,
        reviewRequired: Bool,
        duplicate: Bool,
        replies: [String],
        selectionSessionID: String? = nil,
        selectedReplyIndex: Int? = nil
    ) {
        self.chatID = chatID
        self.chatTitle = chatTitle
        self.importedMessageCount = importedMessageCount
        self.reviewRequired = reviewRequired
        self.duplicate = duplicate
        self.replies = replies
        self.selectionSessionID = selectionSessionID
        self.selectedReplyIndex = selectedReplyIndex
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            header

            if visibleReplies.isEmpty {
                emptyState
            } else {
                ForEach(Array(visibleReplies.enumerated()), id: \.offset) { index, reply in
                    replyCard(reply, index: index)
                }
            }
        }
        .padding(outerPadding)
        .foregroundStyle(.white)
        .background {
            ContainerRelativeShape()
                .fill(
                    LinearGradient(
                        colors: [
                            FrameReplyColor.deepNavy,
                            FrameReplyColor.primary
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .containerShape(ContainerRelativeShape())
    }

    var visibleReplies: [String] {
        Array(
            replies
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(2)
        )
    }

    var headerText: String {
        guard !visibleReplies.isEmpty else {
            return String(localized: "Replies unavailable")
        }
        return String(localized: "\(visibleReplies.count) replies ready")
    }

    var statusText: String {
        if duplicate {
            return String(localized: "No new messages added to \(chatTitle)")
        }

        let messageCount = String(localized: "\(importedMessageCount) messages")
        if reviewRequired {
            return String(
                localized: "\(messageCount) imported to \(chatTitle) · Review required"
            )
        }
        return String(localized: "\(messageCount) imported to \(chatTitle)")
    }

    var showsEmptyState: Bool {
        visibleReplies.isEmpty
    }

    private var previewLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 4
    }

    private var usesCompactSpacing: Bool {
        dynamicTypeSize >= .xxLarge
    }

    private var contentSpacing: CGFloat {
        usesCompactSpacing ? 8 : 12
    }

    private var outerPadding: CGFloat {
        usesCompactSpacing ? 8 : 12
    }

    private var cardVerticalPadding: CGFloat {
        usesCompactSpacing ? 8 : 12
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(
                intent: OpenShortcutImportIntent(
                    chatID: chatID,
                    reviewRequired: reviewRequired
                )
            ) {
                Image(
                    systemName: reviewRequired
                        ? "exclamationmark.bubble" : "arrow.up.forward.app"
                )
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(.white)
                .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .tint(.white)
            .accessibilityLabel(
                reviewRequired ? Text("Review Import") : Text("Open Chat")
            )
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.forward.app")
                .accessibilityHidden(true)

            Text("Open FrameReply to try again.")
                .font(.body)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, cardVerticalPadding)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func replyCard(_ reply: String, index: Int) -> some View {
        if let selectionSessionID {
            Button(
                intent: SelectShortcutReplyIntent(
                    selectionSessionID: selectionSessionID,
                    replyIndex: index
                )
            ) {
                replyCardContent(reply, index: index)
            }
            .buttonStyle(.plain)
            .tint(.white)
            .accessibilityLabel(Text("Suggested reply \(index + 1): \(reply)"))
            .accessibilityValue(
                selectedReplyIndex == index ? Text("Selected") : Text("")
            )
            .accessibilityHint(Text("Select this reply"))
        } else {
            replyCardContent(reply, index: index)
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: reply))
                .accessibilityHint(Text("Touch and hold to copy the complete reply"))
        }
    }

    private func replyCardContent(_ reply: String, index: Int) -> some View {
        let isSelected = selectedReplyIndex == index

        return HStack(alignment: .top, spacing: 10) {
            Group {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                } else {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                .white.opacity(isSelected ? 0.34 : 0.16),
                in: Circle()
            )
            .accessibilityHidden(true)

            Text(reply)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(previewLineLimit)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, cardVerticalPadding)
        .background(
            .white.opacity(isSelected ? 0.20 : 0.10),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    .white.opacity(isSelected ? 0.68 : 0.18),
                    lineWidth: isSelected ? 2 : 1
                )
        }
    }

}

#if DEBUG
    #Preview("Reply Confirmation · Dark") {
        ShortcutRepliesSnippet(
            chatID: "preview-chat",
            chatTitle: "natalie",
            importedMessageCount: 9,
            reviewRequired: false,
            duplicate: false,
            replies: [
                "Мне очень нравится набережная. Там открывается прекрасный вид на Волгу и Оку.",
                "Люблю гулять по Кремлю. Это красивое и историческое место в центре города."
            ],
            selectionSessionID: "preview-session",
            selectedReplyIndex: 0
        )
        .padding()
        .background(.black)
        .environment(\.colorScheme, .dark)
    }

    #Preview("Reply Confirmation · Light · Review") {
        ShortcutRepliesSnippet(
            chatID: "preview-chat",
            chatTitle: "Maya 🌻",
            importedMessageCount: 1,
            reviewRequired: true,
            duplicate: false,
            replies: [
                "That sounds wonderful — I’d love to join! ✨ Let me check the timing and get back to you.",
                "يسعدني ذلك جدًا. دعيني أتأكد من الموعد ثم أرسل لك التفاصيل كاملة."
            ],
            selectionSessionID: "preview-session",
            selectedReplyIndex: 1
        )
        .padding()
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    #Preview("Reply Confirmation · Accessibility") {
        ShortcutRepliesSnippet(
            chatID: "preview-chat",
            chatTitle: "Long conversation",
            importedMessageCount: 42,
            reviewRequired: false,
            duplicate: false,
            replies: [
                String(
                    repeating: "A thoughtful long reply that remains complete when copied. ",
                    count: 9
                ),
                String(
                    repeating: "Another long suggestion for testing truncation and layout. ",
                    count: 9
                )
            ],
            selectionSessionID: "preview-session",
            selectedReplyIndex: 0
        )
        .padding()
        .background(.black)
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .accessibility2)
    }

    #Preview("Shortcut Result · Unavailable") {
        ShortcutRepliesSnippet(
            chatID: "preview-chat",
            chatTitle: "natalie",
            importedMessageCount: 9,
            reviewRequired: false,
            duplicate: true,
            replies: []
        )
        .padding()
        .background(.white)
        .environment(\.colorScheme, .light)
    }
#endif

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
