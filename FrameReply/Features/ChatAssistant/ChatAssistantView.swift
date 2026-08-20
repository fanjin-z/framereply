//
//  ChatAssistantView.swift
//  FrameReply
//

import PhotosUI
import SwiftData
import SwiftUI

struct ChatAssistantView: View {
    let chat: Chat
    @ObservedObject var providerStore: ProviderStore
    private let repository: ChatRepository
    let onDetailsTap: () -> Void
    let onDeleted: () -> Void
    let onMergedIntoChat: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var isHistoryPresented = false
    @State private var isImportSourcePresented = false
    @State private var isReviewPresented = false
    @State private var isMergeConfirmationPresented = false
    @State private var isRenamePresented = false
    @State private var renameDraft = ""
    @State private var isEditNamesPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isDirectConversionPresented = false
    @State private var actionErrorMessage: String?
    @State private var selectedScreenshotItems: [PhotosPickerItem] = []
    @State private var photoLoadErrorMessage: String?
    @State private var importTask: Task<Void, Never>?
    @State private var activeImportTaskID: UUID?
    @State private var replyGuidance = ""
    @State private var goalDraft = ""
    @State private var goalEditorDraft = ""
    @State private var isGoalEditorPresented = false
    @FocusState private var isReplyGuidanceFocused: Bool
    @State private var didLoadContext = false
    @State private var replyRefreshNoticeState = ReplyRefreshNoticeState()
    @State private var isImportStatusDismissed = false
    @State private var copiedReplyID: UUID?
    @Query private var currentChatRecords: [ChatRecord]
    @Query private var messageRecords: [ChatMessageRecord]
    @Query private var chatContextRecords: [ChatContextRecord]
    @Query private var suggestedReplyCacheRecords: [SuggestedReplyCacheRecord]
    @Query private var mergeCandidateRecords: [ChatRecord]
    @Query private var mergeCandidateContextRecords: [ChatContextRecord]
    @StateObject private var suggestedRepliesModel: SuggestedRepliesViewModel
    @StateObject private var importModel: InAppScreenshotImportViewModel

    init(
        chat: Chat,
        providerStore: ProviderStore,
        repository: ChatRepository,
        suggestedRepliesCoordinator: any SuggestedRepliesCoordinating,
        presentImportReviewOnAppear: Bool = false,
        onDetailsTap: @escaping () -> Void,
        onDeleted: @escaping () -> Void,
        onMergedIntoChat: @escaping (String) -> Void
    ) {
        self.chat = chat
        self.providerStore = providerStore
        self.repository = repository
        self.onDetailsTap = onDetailsTap
        self.onDeleted = onDeleted
        self.onMergedIntoChat = onMergedIntoChat
        _isReviewPresented = State(initialValue: presentImportReviewOnAppear)
        let chatID = chat.id
        _currentChatRecords = Query(
            filter: #Predicate<ChatRecord> { $0.id == chatID }
        )
        _messageRecords = Query(
            filter: #Predicate<ChatMessageRecord> { $0.chatID == chatID },
            sort: \ChatMessageRecord.sortIndex
        )
        _chatContextRecords = Query(
            filter: #Predicate<ChatContextRecord> { $0.chatID == chatID }
        )
        _suggestedReplyCacheRecords = Query(
            filter: #Predicate<SuggestedReplyCacheRecord> { $0.chatID == chatID }
        )
        _mergeCandidateRecords = Query(
            filter: #Predicate<ChatRecord> { $0.id != chatID },
            sort: \ChatRecord.updatedAt,
            order: .reverse
        )
        _mergeCandidateContextRecords = Query(
            filter: #Predicate<ChatContextRecord> { $0.chatID != chatID }
        )
        _suggestedRepliesModel = StateObject(
            wrappedValue: SuggestedRepliesViewModel(
                chatID: chatID,
                coordinator: suggestedRepliesCoordinator
            )
        )
        _importModel = StateObject(
            wrappedValue: InAppScreenshotImportViewModel(
                providerStore: providerStore,
                repository: repository,
                destinationChatID: chatID
            )
        )
    }

    private var provisionalIdentity: ProvisionalIdentityInterpretation? {
        ProvisionalIdentityResolver.resolve(
            chat: currentChatRecord,
            messages: messageRecords,
            previouslyUsedSelfAliasLabels:
                ProvisionalIdentityResolver.previouslyUsedSelfAliasLabels(
                    in: chatContextRecords + mergeCandidateContextRecords
                )
        )
    }

    private var messages: [ChatMessage] {
        messageRecords.map {
            ChatMessage(record: $0, provisionalIdentity: provisionalIdentity)
        }
    }

    private var latestMessages: [ChatMessage] {
        Array(messages.suffix(3))
    }

    private var conversationStrategy: String {
        suggestedRepliesModel.conversationStrategy.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var noReplyState: SuggestedRepliesNoReplyState? {
        guard suggestedRepliesModel.replies.isEmpty,
            !conversationStrategy.isEmpty,
            let latestSender = messages.last?.sender
        else { return nil }

        switch latestSender {
        case .user:
            return .awaitingResponse
        case .groupParticipant:
            return .groupPause
        case .otherParticipant, .unknown:
            return nil
        }
    }

    private var currentChatRecord: ChatRecord? {
        currentChatRecords.first
    }

    @MainActor private var displayedChat: Chat {
        currentChatRecord.map {
            Chat(record: $0, provisionalIdentity: provisionalIdentity)
        } ?? chat
    }

    private var currentChatContext: ChatContextRecord? {
        chatContextRecords.first
    }

    private var isDirectChat: Bool {
        (currentChatRecord?.conversationKind ?? chat.conversationKind) == .direct
    }

    private var participantAliases: [ChatParticipantAlias] {
        currentChatContext?.participantAliases ?? []
    }

    private var isManagementDisabled: Bool {
        activeImportTaskID != nil || importModel.isLoading || suggestedRepliesModel.isLoading
    }

    private var isCurrentChatProvisional: Bool {
        currentChatRecord?.isProvisional ?? chat.isProvisional
    }

    private var hasCurrentKindReview: Bool {
        currentChatRecord?.importReviewState?.hasKindReview == true
    }

    private var hasSuggestedMatch: Bool {
        currentChatRecord?.importReviewState?.suggestedMatchChatID != nil
    }

    private var unknownSenderCount: Int {
        messageRecords.filter { $0.senderKind == "unknown" }.count
    }

    private var mergeCandidates: [ChatRecord] {
        return mergeCandidateRecords.filter {
            !$0.requiresImportIdentityReview
        }
    }

    private func mergeCandidateLabel(_ candidate: ChatRecord) -> String {
        guard
            let alias =
                mergeCandidateContextRecords
                .first(where: { $0.chatID == candidate.id })?
                .participantAliases
                .first(where: {
                    ChatParticipantAlias.normalizedKey($0.displayLabel)
                        != ChatParticipantAlias.normalizedKey(candidate.title)
                })
        else {
            return candidate.displayTitle()
        }
        return String(
            localized: AppStrings.Chat.mergeCandidate(
                title: candidate.displayTitle(), alias: alias.displayLabel
            )
        )
    }

    private var shouldShowImportReviewCard: Bool {
        currentChatRecord?.requiresImportReview == true || unknownSenderCount > 0
    }

    private var shouldShowImportNotice: Bool {
        importModel.isLoading
            || (!isImportStatusDismissed && importStatusMessage != nil)
    }

    private var shouldShowReplyRefreshNotice: Bool {
        replyRefreshNoticeState.isVisible
    }

    private var shouldShowStatusRail: Bool {
        shouldShowImportNotice
            || shouldShowReplyRefreshNotice
            || shouldShowImportReviewCard
    }

    private var replyCacheKey: Int {
        var hasher = Hasher()
        for message in messageRecords {
            hasher.combine(message.id)
            hasher.combine(message.senderKind)
            hasher.combine(message.senderName)
            hasher.combine(message.text)
            hasher.combine(message.sortIndex)
        }
        for context in chatContextRecords + mergeCandidateContextRecords {
            hasher.combine(context.chatID)
            for alias in context.selfAliases {
                hasher.combine(alias.displayLabel)
            }
        }
        if let cache = currentLanguageCache {
            hasher.combine(cache.inputFingerprint)
            hasher.combine(cache.repliesJSON)
            hasher.combine(cache.promptVersion)
            hasher.combine(cache.generatedAt)
        }
        hasher.combine(localizationContext.languageIdentifier)
        hasher.combine(providerStore.activeProvider?.platform.rawValue)
        hasher.combine(providerStore.activeProvider?.tier.rawValue)
        return hasher.finalize()
    }

    private var assistantStatusRail: some View {
        VStack(spacing: 0) {
            importNotice

            if shouldShowReplyRefreshNotice {
                if shouldShowImportNotice {
                    assistantStatusDivider
                }

                replyRefreshNotice
            }

            if shouldShowImportReviewCard {
                if shouldShowImportNotice || shouldShowReplyRefreshNotice {
                    assistantStatusDivider
                }

                ChatImportReviewCard(
                    isProvisional: isCurrentChatProvisional,
                    unknownSenderCount: unknownSenderCount,
                    canMerge: !mergeCandidates.isEmpty,
                    provisionalIdentity: provisionalIdentity,
                    hasKindReview: hasCurrentKindReview,
                    conversationKind: currentChatRecord?.conversationKind
                        ?? chat.conversationKind,
                    hasSuggestedMatch: hasSuggestedMatch,
                    onKeepAsNew: confirmCurrentChat,
                    onConfirmIdentity: confirmInferredIdentity,
                    onMergeTap: {
                        isMergeConfirmationPresented = true
                    },
                    onReviewSenders: {
                        isReviewPresented = true
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(FrameReplyColor.surfaceContainerLow.opacity(0.42))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(FrameReplyColor.outlineVariant.opacity(0.42), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant-status-rail")
    }

    @ViewBuilder private var importNotice: some View {
        if shouldShowImportNotice {
            if importModel.isLoading {
                ChatAssistantNoticeRow(
                    symbolName: "sparkles",
                    message: importModel.importKind == .copiedMessages
                        ? importProgressMessage(for: "chat text")
                        : importProgressMessage(for: "selected screenshots"),
                    isLoading: true,
                    actionTitle: "Cancel",
                    onAction: cancelImport
                )
                .accessibilityIdentifier("assistant-import-notice")
            } else if let importStatusMessage {
                ChatAssistantNoticeRow(
                    symbolName: importStatusSymbolName,
                    message: importStatusMessage,
                    onDismiss: dismissImportStatus
                )
                .accessibilityIdentifier("assistant-import-notice")
            }
        }
    }

    @ViewBuilder private var replyRefreshNotice: some View {
        if suggestedRepliesModel.isLoading {
            ChatAssistantNoticeRow(
                symbolName: "arrow.triangle.2.circlepath",
                message: String(localized: "Refreshing replies…"),
                isLoading: true
            )
            .accessibilityIdentifier("assistant-reply-refresh-notice")
        } else {
            ChatAssistantNoticeRow(
                symbolName: "arrow.triangle.2.circlepath",
                message: String(
                    localized: "The reply brief changed. Update when you’re ready."
                ),
                actionTitle: "Update",
                onAction: generateReplies,
                onDismiss: { replyRefreshNoticeState.dismiss() }
            )
            .accessibilityIdentifier("assistant-reply-refresh-notice")
        }
    }

    private var assistantStatusDivider: some View {
        Divider()
            .overlay(FrameReplyColor.outlineVariant.opacity(0.42))
            .padding(.leading, 42)
    }

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if shouldShowStatusRail {
                        assistantStatusRail
                    }

                    RecentChatSection(
                        messages: latestMessages,
                        onHistoryTap: {
                            isHistoryPresented = true
                        }
                    )

                    ReplyBriefSummaryCard(
                        goal: goalDraft,
                        personaID: currentChatContext?.personaID,
                        onGoalTap: presentGoalEditor,
                        onPersonaSelect: assignPersona
                    )

                    SuggestedRepliesSection(
                        replies: suggestedRepliesModel.replies,
                        copiedReplyID: copiedReplyID,
                        isLoading: suggestedRepliesModel.isLoading,
                        needsRefresh: replyRefreshNoticeState.needsRefresh,
                        noReplyState: noReplyState,
                        errorMessage: suggestedRepliesModel.errorMessage,
                        onCopy: copyReply,
                        onRetry: generateReplies,
                        onGenerate: generateReplies
                    )

                    if !conversationStrategy.isEmpty {
                        ConversationStrategyCard(conversationStrategy: conversationStrategy)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("chat-assistant-screen")

            if isReplyGuidanceFocused && !isGoalEditorPresented {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        KeyboardDismissal.dismiss()
                        isReplyGuidanceFocused = false
                    }
                    .accessibilityHidden(true)
                    .zIndex(1)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ChatAssistantTopBar(
                chat: displayedChat,
                isDirectChat: isDirectChat,
                isManagementDisabled: isManagementDisabled,
                onBackTap: {
                    dismiss()
                },
                onDetailsTap: onDetailsTap,
                onEditNamesTap: presentNameEditor,
                onConversationTypeTap: updateConversationType,
                onDeleteTap: presentDeleteConfirmation
            )
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if !isGoalEditorPresented {
                ConversationUpdateComposer(
                    replyGuidance: $replyGuidance,
                    isGuidanceFocused: $isReplyGuidanceFocused,
                    isImporting: importModel.isLoading,
                    isUpdatingReplies: suggestedRepliesModel.isLoading,
                    onAddMessagesTap: {
                        isImportSourcePresented = true
                    },
                    onSubmitGuidance: submitReplyGuidance
                )
            }
        }
        .overlay {
            if isGoalEditorPresented {
                ReplyGoalDialog(
                    goalDraft: $goalEditorDraft,
                    onCancel: dismissGoalEditor,
                    onSave: saveGoalEditor
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(10)
            }
        }
        .interactiveSwipeBackEnabled()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isHistoryPresented) {
            ChatHistorySheet(
                chat: displayedChat,
                provisionalIdentity: provisionalIdentity
            )
        }
        .sheet(isPresented: $isImportSourcePresented) {
            ChatImportSourceSheet(
                screenshotSelection: $selectedScreenshotItems,
                draftingInput: $replyGuidance,
                onPaste: { items in
                    startImportTask {
                        await importCopiedMessages(items)
                    }
                }
            )
        }
        .sheet(isPresented: $isReviewPresented) {
            ChatImportReviewSheet(
                chatID: chat.id,
                repository: repository,
                onMerged: onMergedIntoChat
            )
        }
        .sheet(isPresented: $isEditNamesPresented) {
            EditParticipantNamesSheet(
                chatID: chat.id,
                displayName: displayedChat.name,
                aliases: participantAliases,
                repository: repository
            )
        }
        .sheet(isPresented: $isDirectConversionPresented) {
            DirectCounterpartSelectionSheet(
                candidateNames: detectedParticipantNames,
                onSelect: convertToDirect
            )
        }
        .alert("Rename Chat", isPresented: $isRenamePresented) {
            TextField("Chat name", text: $renameDraft)
            Button("Save", action: renameChat)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a clear name for this chat.")
        }
        .confirmationDialog(
            "Delete chat with \(displayedChat.name)?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive, action: deleteChat)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this chat and its data. This can’t be undone.")
        }
        .confirmationDialog(
            "Merge Imported Chat",
            isPresented: $isMergeConfirmationPresented,
            titleVisibility: .visible
        ) {
            ForEach(mergeCandidates) { candidate in
                Button("Merge Into \(mergeCandidateLabel(candidate))") {
                    mergeChat(into: candidate.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move this imported chat into an existing chat. This can’t be undone.")
        }
        .alert("Could Not Update Chat", isPresented: actionErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: actionErrorMessage ?? String(localized: AppStrings.Common.tryAgain))
        }
        .task(id: replyCacheKey) {
            loadCachedReplies()
        }
        .task {
            loadChatContext()
        }
        .task(id: shouldShowImportReviewCard) {
            recordReviewExposureIfNeeded()
        }
        .onChange(of: selectedScreenshotItems) { _, items in
            guard !items.isEmpty else { return }
            isImportSourcePresented = false
            startImportTask {
                await importSelectedScreenshots(items)
            }
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    actionErrorMessage = nil
                }
            }
        )
    }

    private var importStatusMessage: String? {
        if let photoLoadErrorMessage {
            return photoLoadErrorMessage
        }
        if let errorMessage = importModel.errorMessage {
            return errorMessage
        }
        if let result = importModel.result {
            if let replyErrorMessage = result.replyErrorMessage {
                return "\(result.message) Suggested replies could not be generated: "
                    + replyErrorMessage
            }
            return result.message
        }
        return nil
    }

    private var importStatusSymbolName: String {
        if hasImportError {
            return "exclamationmark.triangle.fill"
        }
        if importModel.result?.replyErrorMessage != nil
            || importModel.result?.outcome.reviewRequired == true
        {
            return "exclamationmark.bubble.fill"
        }
        return "checkmark.circle.fill"
    }

    private var hasImportError: Bool {
        photoLoadErrorMessage != nil || importModel.errorMessage != nil
    }

    private func dismissImportError() {
        photoLoadErrorMessage = nil
        importModel.dismissError()
    }

    private func dismissImportStatus() {
        isImportStatusDismissed = true
        if hasImportError {
            dismissImportError()
        }
    }

    private func importProgressMessage(for source: String) -> String {
        switch importModel.phase {
        case .analyzing:
            "Analyzing \(source)…"
        case .generatingReplies:
            "Generating replies…"
        }
    }

    private func cancelImport() {
        importTask?.cancel()
    }

    private func startImportTask(operation: @escaping @MainActor () async -> Void) {
        importTask?.cancel()
        let taskID = UUID()
        activeImportTaskID = taskID
        importTask = Task { @MainActor in
            await operation()
            guard activeImportTaskID == taskID else { return }
            activeImportTaskID = nil
            importTask = nil
        }
    }

    private func importSelectedScreenshots(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        defer { selectedScreenshotItems = [] }
        photoLoadErrorMessage = nil
        isImportStatusDismissed = false

        do {
            let imageDataList = try await ChatScreenshotPhotoLoader.loadData(from: items)
            let draftingInput = replyGuidance
            if let result = await importModel.importScreenshots(
                imageDataList,
                draftingInput: draftingInput
            ), result.chatID == chat.id {
                suggestedRepliesModel.loadCached(localization: localizationContext)
                if result.replies != nil {
                    replyRefreshNoticeState.generationSucceeded()
                    clearReplyGuidance(ifMatching: draftingInput)
                }
                recordMeaningfulReviewAction()
            }
        } catch is CancellationError {
        } catch {
            photoLoadErrorMessage = error.localizedDescription
            isImportStatusDismissed = false
        }
    }

    private func importCopiedMessages(_ items: [String]) async {
        guard !items.isEmpty else { return }
        photoLoadErrorMessage = nil
        isImportStatusDismissed = false

        let draftingInput = replyGuidance
        if let result = await importModel.importCopiedMessages(
            items,
            draftingInput: draftingInput
        ), result.chatID == chat.id {
            suggestedRepliesModel.loadCached(localization: localizationContext)
            if result.replies != nil {
                replyRefreshNoticeState.generationSucceeded()
                clearReplyGuidance(ifMatching: draftingInput)
            }
            recordMeaningfulReviewAction()
        }
    }

    private func copyReply(_ reply: SuggestedReply) {
        ClipboardWriter.copy(reply.text)

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            copiedReplyID = reply.id
        }
        recordMeaningfulReviewAction()
    }

    private func generateReplies() {
        Task {
            if await suggestedRepliesModel.generate(
                draftingInput: nil,
                localization: localizationContext
            ) {
                replyRefreshNoticeState.generationSucceeded()
                recordMeaningfulReviewAction()
            }
        }
    }

    private func submitReplyGuidance() {
        let submittedGuidance = replyGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedGuidance.isEmpty,
            !suggestedRepliesModel.isLoading,
            !importModel.isLoading
        else {
            return
        }

        Task {
            if await suggestedRepliesModel.generate(
                draftingInput: submittedGuidance,
                localization: localizationContext
            ) {
                replyRefreshNoticeState.generationSucceeded()
                clearReplyGuidance(ifMatching: submittedGuidance)
                recordMeaningfulReviewAction()
            }
        }
    }

    private func clearReplyGuidance(ifMatching submittedGuidance: String) {
        guard
            replyGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
                == submittedGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return
        }
        replyGuidance = ""
    }

    private func loadCachedReplies() {
        suggestedRepliesModel.loadCached(localization: localizationContext)
    }

    private func confirmCurrentChat() {
        do {
            try repository.confirmProvisionalChat(
                chatID: chat.id,
                name: displayedChat.name
            )
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func confirmInferredIdentity() {
        guard let provisionalIdentity else { return }
        do {
            try repository.resolveUnknownSenderLabels(
                chatID: chat.id,
                selfLabel: provisionalIdentity.selfDisplayLabel
            )
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func mergeChat(into targetChatID: String) {
        do {
            try repository.mergeProvisionalChat(chat.id, into: targetChatID)
            if try repository.chat(id: chat.id) == nil {
                onMergedIntoChat(targetChatID)
            }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func presentNameEditor() {
        guard !isManagementDisabled else { return }
        if isDirectChat {
            isEditNamesPresented = true
        } else {
            renameDraft = displayedChat.name
            isRenamePresented = true
        }
    }

    private func updateConversationType() {
        guard !isManagementDisabled else { return }
        if isDirectChat {
            convertToGroup()
        } else {
            isDirectConversionPresented = true
        }
    }

    private func presentDeleteConfirmation() {
        guard !isManagementDisabled else { return }
        isDeleteConfirmationPresented = true
    }

    private func renameChat() {
        guard !isManagementDisabled else { return }
        do {
            try repository.renameChat(id: chat.id, name: renameDraft)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func deleteChat() {
        guard !isManagementDisabled else { return }
        cancelImport()
        do {
            try repository.deleteChat(id: chat.id)
            onDeleted()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private var detectedParticipantNames: [String] {
        var seen = Set<String>()
        return messageRecords.compactMap { message in
            guard message.senderKind != "user",
                let name = ParticipantLabelNormalizer.displayLabel(message.senderName),
                let key = ParticipantLabelNormalizer.key(name),
                seen.insert(key).inserted
            else {
                return nil
            }
            return name
        }
    }

    private func convertToGroup() {
        guard !isManagementDisabled else { return }
        do {
            try repository.reclassifyConversation(chatID: chat.id, to: .group)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func convertToDirect(_ displayName: String) {
        guard !isManagementDisabled else { return }
        do {
            try repository.reclassifyConversation(
                chatID: chat.id,
                to: .direct,
                directDisplayName: displayName
            )
            isDirectConversionPresented = false
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func loadChatContext() {
        do {
            let context = try repository.ensureChatContext(chatID: chat.id)
            goalDraft = context.currentInteractionGoal
            didLoadContext = true
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func presentGoalEditor() {
        goalEditorDraft = goalDraft
        isReplyGuidanceFocused = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            isGoalEditorPresented = true
        }
    }

    private func dismissGoalEditor() {
        KeyboardDismissal.dismiss()
        goalEditorDraft = goalDraft
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            isGoalEditorPresented = false
        }
    }

    private func saveGoalEditor() {
        guard didLoadContext else { return }
        let normalizedGoal = String(
            goalEditorDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)
        )
        do {
            if try repository.updateInteractionGoal(chatID: chat.id, goal: normalizedGoal) {
                goalDraft = normalizedGoal
                replyRefreshNoticeState.replyBriefChanged(
                    hasExistingReplyCache: currentLanguageCache != nil
                )
            }
            KeyboardDismissal.dismiss()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                isGoalEditorPresented = false
            }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func assignPersona(_ personaID: UUID) {
        do {
            if try repository.assignPersona(personaID: personaID, toChatID: chat.id) {
                replyRefreshNoticeState.replyBriefChanged(
                    hasExistingReplyCache: currentLanguageCache != nil
                )
            }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func recordReviewExposureIfNeeded() {
        guard shouldShowImportReviewCard else {
            return
        }
        do {
            try repository.recordImportReviewExposure(chatID: chat.id)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func recordMeaningfulReviewAction() {
        do {
            try repository.recordImportReviewMeaningfulAction(chatID: chat.id)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private var localizationContext: LocalizationContext {
        LocalizationContext(locale: locale)
    }

    private var currentLanguageCache: SuggestedReplyCacheRecord? {
        suggestedReplyCacheRecords.first {
            $0.appLanguage == localizationContext.languageIdentifier
        }
    }
}

struct ReplyRefreshNoticeState: Equatable {
    private(set) var needsRefresh = false
    private(set) var isDismissed = false

    var isVisible: Bool {
        needsRefresh && !isDismissed
    }

    mutating func replyBriefChanged(hasExistingReplyCache: Bool) {
        needsRefresh = hasExistingReplyCache
        isDismissed = false
    }

    mutating func dismiss() {
        guard needsRefresh else { return }
        isDismissed = true
    }

    mutating func generationSucceeded() {
        needsRefresh = false
        isDismissed = false
    }
}

private struct ChatAssistantNoticeRow: View {
    let symbolName: String
    let message: String
    var isLoading = false
    var actionTitle: LocalizedStringResource? = nil
    var onAction: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(FrameReplyColor.primary)
            .tint(FrameReplyColor.primary)
            .frame(width: 20)

            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.primary)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, onDismiss == nil ? 12 : 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }
}

private struct ChatImportReviewCard: View {
    let isProvisional: Bool
    let unknownSenderCount: Int
    let canMerge: Bool
    let provisionalIdentity: ProvisionalIdentityInterpretation?
    let hasKindReview: Bool
    let conversationKind: ChatConversationKind
    let hasSuggestedMatch: Bool
    let onKeepAsNew: () -> Void
    let onConfirmIdentity: () -> Void
    let onMergeTap: () -> Void
    let onReviewSenders: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FrameReplyColor.primary.opacity(0.88))

            Text(nudgeText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 6)

            Button(primaryActionTitle, action: primaryAction)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(minHeight: 44)
                .buttonStyle(.plain)

            if hasSecondaryActions {
                Menu {
                    if isProvisional && provisionalIdentity != nil {
                        Button("Confirm Identity", action: onConfirmIdentity)
                    }
                    if canMerge {
                        Button("Merge into...", action: onMergeTap)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FrameReplyColor.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.trailing, hasSecondaryActions ? 2 : 12)
        .padding(.vertical, 2)
        .frame(minHeight: 48)
        .accessibilityIdentifier("assistant-import-review-notice")
    }

    private var nudgeText: String {
        if hasKindReview, conversationKind == .group {
            return "Converted to Group"
        }
        if hasKindReview {
            return "This may be a group chat"
        }
        if hasSuggestedMatch {
            return "Possible matching chat"
        }
        if let provisionalIdentity {
            return "Assuming you are \(provisionalIdentity.selfDisplayLabel)"
        }
        if isProvisional && unknownSenderCount > 0 {
            return "Review imported chat"
        }
        if unknownSenderCount > 0 {
            return "Review senders"
        }
        return "Imported chat"
    }

    private var iconName: String {
        if hasKindReview { return "person.2.fill" }
        if hasSuggestedMatch { return "link.badge.plus" }
        return unknownSenderCount > 0
            ? "person.crop.circle.badge.questionmark" : "tray.and.arrow.down"
    }

    private var primaryActionTitle: String {
        unknownSenderCount > 0 || hasKindReview || hasSuggestedMatch ? "Review" : "Keep"
    }

    private var primaryAction: () -> Void {
        unknownSenderCount > 0 || hasKindReview || hasSuggestedMatch
            ? onReviewSenders : onKeepAsNew
    }

    private var hasSecondaryActions: Bool {
        (isProvisional && provisionalIdentity != nil) || canMerge
    }
}
