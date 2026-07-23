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
    let onDetailsTap: () -> Void
    let onMergedIntoChat: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var isHistoryPresented = false
    @State private var isReplyNotePresented = false
    @State private var isReplyBriefPresented = false
    @State private var isImportSourcePresented = false
    @State private var isReviewPresented = false
    @State private var isMergeConfirmationPresented = false
    @State private var actionErrorMessage: String?
    @State private var selectedScreenshotItems: [PhotosPickerItem] = []
    @State private var photoLoadErrorMessage: String?
    @State private var importDraftingInput = ""
    @State private var importTask: Task<Void, Never>?
    @State private var replyNote = ""
    @State private var lastSubmittedReplyNote = ""
    @State private var goalDraft = ""
    @State private var didLoadContext = false
    @State private var needsReplyRefresh = false
    @State private var copiedReplyID: UUID?
    @Query private var currentChatRecords: [ChatRecord]
    @Query private var messageRecords: [ChatMessageRecord]
    @Query private var chatContextRecords: [ChatContextRecord]
    @Query private var chatMemoryRecords: [ChatMemoryRecord]
    @Query private var suggestedReplyCacheRecords: [SuggestedReplyCacheRecord]
    @Query private var mergeCandidateRecords: [ChatRecord]
    @Query private var mergeCandidateContextRecords: [ChatContextRecord]
    @StateObject private var suggestedRepliesModel: SuggestedRepliesViewModel
    @StateObject private var importModel: InAppScreenshotImportViewModel

    init(
        chat: Chat,
        providerStore: ProviderStore,
        presentImportReviewOnAppear: Bool = false,
        onDetailsTap: @escaping () -> Void,
        onMergedIntoChat: @escaping (String) -> Void
    ) {
        self.chat = chat
        self.providerStore = providerStore
        self.onDetailsTap = onDetailsTap
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
        _chatMemoryRecords = Query(
            filter: #Predicate<ChatMemoryRecord> { $0.chatID == chatID },
            sort: \ChatMemoryRecord.createdAt
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
                coordinator: SuggestedRepliesCoordinator(providerStore: providerStore)
            )
        )
        _importModel = StateObject(
            wrappedValue: InAppScreenshotImportViewModel(
                providerStore: providerStore,
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

    private var isCurrentChatProvisional: Bool {
        currentChatRecord?.isProvisional ?? chat.isProvisional
    }

    private var unknownSenderCount: Int {
        messageRecords.filter { $0.senderKind == "unknown" }.count
    }

    private var mergeCandidates: [ChatRecord] {
        mergeCandidateRecords.filter { !$0.requiresImportIdentityReview }
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
        isCurrentChatProvisional || unknownSenderCount > 0
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

    private var contextRevisionKey: Int {
        var hasher = Hasher()
        if let context = currentChatContext {
            hasher.combine(context.currentInteractionGoal)
            hasher.combine(context.personaID)
            hasher.combine(context.personaAssignedAt)
        }
        for memory in chatMemoryRecords {
            hasher.combine(memory.id)
            hasher.combine(memory.text)
            hasher.combine(memory.origin)
            hasher.combine(memory.certainty)
            hasher.combine(memory.status)
            hasher.combine(memory.updatedAt)
        }
        return hasher.finalize()
    }

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if shouldShowImportReviewCard {
                        ChatImportReviewCard(
                            isProvisional: isCurrentChatProvisional,
                            unknownSenderCount: unknownSenderCount,
                            canMerge: !mergeCandidates.isEmpty,
                            provisionalIdentity: provisionalIdentity,
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

                    VStack(alignment: .leading, spacing: 14) {
                        RecentChatSection(
                            messages: latestMessages,
                            onHistoryTap: {
                                isHistoryPresented = true
                            }
                        )

                        ConversationUpdateControls(
                            isImporting: importModel.isLoading,
                            hasReplyNote: !replyNote.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty,
                            onAddMessagesTap: {
                                isImportSourcePresented = true
                            },
                            onReplyNoteTap: {
                                isReplyNotePresented = true
                            }
                        )

                        if importModel.isLoading {
                            ScreenshotImportStatusCard(
                                symbolName: "sparkles",
                                message: importModel.importKind == .copiedMessages
                                    ? importProgressMessage(for: "chat text")
                                    : importProgressMessage(for: "selected screenshots"),
                                isLoading: true,
                                onCancel: cancelImport
                            )
                        } else if let importStatusMessage {
                            ScreenshotImportStatusCard(
                                symbolName: importStatusSymbolName,
                                message: importStatusMessage,
                                isLoading: false
                            )
                        }
                    }

                    ReplyBriefSummaryCard(
                        goal: goalDraft,
                        personaID: currentChatContext?.personaID,
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                isReplyBriefPresented = true
                            }
                        }
                    )

                    SuggestedRepliesSection(
                        replies: suggestedRepliesModel.replies,
                        copiedReplyID: copiedReplyID,
                        isLoading: suggestedRepliesModel.isLoading,
                        needsRefresh: needsReplyRefresh,
                        errorMessage: suggestedRepliesModel.errorMessage,
                        onCopy: copyReply,
                        onRetry: generateReplies,
                        onGenerate: generateReplies
                    )

                    if !conversationStrategy.isEmpty {
                        ConversationStrategyCard(conversationStrategy: conversationStrategy)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ChatAssistantTopBar(
                chat: displayedChat,
                onBackTap: {
                    dismiss()
                },
                onDetailsTap: onDetailsTap
            )
        }
        .overlay {
            if isReplyBriefPresented {
                ReplyBriefDialog(
                    goalDraft: $goalDraft,
                    personaID: currentChatContext?.personaID,
                    onGoalCommit: commitGoal,
                    onPersonaSelect: assignPersona,
                    onDismiss: dismissReplyBrief
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
        .sheet(isPresented: $isReplyNotePresented) {
            AddReplyNoteSheet(note: $replyNote)
        }
        .sheet(isPresented: $isImportSourcePresented) {
            ChatImportSourceSheet(
                screenshotSelection: $selectedScreenshotItems,
                draftingInput: $importDraftingInput,
                onPaste: { items in
                    importTask?.cancel()
                    importTask = Task {
                        await importCopiedMessages(items)
                    }
                }
            )
        }
        .sheet(isPresented: $isReviewPresented) {
            ChatImportReviewSheet(chatID: chat.id, onMerged: onMergedIntoChat)
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
            if !items.isEmpty {
                isImportSourcePresented = false
            }
            importTask?.cancel()
            importTask = Task {
                await importSelectedScreenshots(items)
            }
        }
        .onChange(of: isReplyNotePresented) { wasPresented, isPresented in
            if wasPresented && !isPresented {
                handleReplyNoteDismissal()
            }
        }
        .onChange(of: contextRevisionKey) { oldValue, newValue in
            if didLoadContext && oldValue != newValue
                && !suggestedRepliesModel.isLoading && !importModel.isLoading
            {
                needsReplyRefresh = currentLanguageCache != nil
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
        if photoLoadErrorMessage != nil || importModel.errorMessage != nil {
            return "exclamationmark.triangle.fill"
        }
        if importModel.result?.replyErrorMessage != nil
            || importModel.result?.outcome.reviewRequired == true
        {
            return "exclamationmark.bubble.fill"
        }
        return "checkmark.circle.fill"
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

    private func importSelectedScreenshots(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        defer { selectedScreenshotItems = [] }
        photoLoadErrorMessage = nil

        do {
            let imageDataList = try await ChatScreenshotPhotoLoader.loadData(from: items)
            let draftingInput = importDraftingInput
            if let result = await importModel.importScreenshots(
                imageDataList,
                draftingInput: draftingInput
            ), result.chatID == chat.id {
                suggestedRepliesModel.loadCached(localization: localizationContext)
                needsReplyRefresh = false
                if result.replies != nil {
                    importDraftingInput = ""
                }
                recordMeaningfulReviewAction()
            }
        } catch is CancellationError {
        } catch {
            photoLoadErrorMessage = error.localizedDescription
        }
    }

    private func importCopiedMessages(_ items: [String]) async {
        guard !items.isEmpty else { return }
        photoLoadErrorMessage = nil

        let draftingInput = importDraftingInput
        if let result = await importModel.importCopiedMessages(
            items,
            draftingInput: draftingInput
        ), result.chatID == chat.id {
            suggestedRepliesModel.loadCached(localization: localizationContext)
            needsReplyRefresh = false
            if result.replies != nil {
                importDraftingInput = ""
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
            let draftingInput = replyNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if await suggestedRepliesModel.generate(
                draftingInput: draftingInput.isEmpty ? nil : draftingInput,
                localization: localizationContext
            ) {
                needsReplyRefresh = false
                if !draftingInput.isEmpty {
                    replyNote = ""
                    lastSubmittedReplyNote = ""
                }
                recordMeaningfulReviewAction()
            }
        }
    }

    private func loadCachedReplies() {
        suggestedRepliesModel.loadCached(localization: localizationContext)
        needsReplyRefresh =
            currentLanguageCache != nil && suggestedRepliesModel.replies.isEmpty
    }

    private func confirmCurrentChat() {
        do {
            try ChatRepository().confirmProvisionalChat(
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
            try ChatRepository().resolveUnknownSenderLabels(
                chatID: chat.id,
                selfLabel: provisionalIdentity.selfDisplayLabel
            )
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func mergeChat(into targetChatID: String) {
        do {
            let repository = ChatRepository()
            try repository.mergeProvisionalChat(chat.id, into: targetChatID)
            if try repository.chat(id: chat.id) == nil {
                onMergedIntoChat(targetChatID)
            }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func loadChatContext() {
        do {
            let context = try ChatRepository().ensureChatContext(chatID: chat.id)
            goalDraft = context.currentInteractionGoal
            didLoadContext = true
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func commitGoal() {
        guard didLoadContext else { return }
        do {
            if try ChatRepository().updateInteractionGoal(chatID: chat.id, goal: goalDraft) {
                goalDraft = String(
                    goalDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)
                )
                needsReplyRefresh = currentLanguageCache != nil
            }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func dismissReplyBrief() {
        KeyboardDismissal.dismiss()
        commitGoal()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            isReplyBriefPresented = false
        }
    }

    private func assignPersona(_ personaID: UUID) {
        do {
            if try ChatRepository().assignPersona(personaID: personaID, toChatID: chat.id) {
                needsReplyRefresh = currentLanguageCache != nil
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
            try ChatRepository().recordImportReviewExposure(chatID: chat.id)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func recordMeaningfulReviewAction() {
        do {
            try ChatRepository().recordImportReviewMeaningfulAction(chatID: chat.id)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func handleReplyNoteDismissal() {
        let trimmedNote = replyNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty, trimmedNote != lastSubmittedReplyNote else {
            return
        }
        lastSubmittedReplyNote = trimmedNote
        recordMeaningfulReviewAction()
        guard !messageRecords.isEmpty else { return }
        Task {
            if await suggestedRepliesModel.generate(
                draftingInput: trimmedNote,
                localization: localizationContext
            ) {
                needsReplyRefresh = false
                replyNote = ""
                lastSubmittedReplyNote = ""
                recordMeaningfulReviewAction()
            }
        }
    }

    private var localizationContext: LocalizationContext {
        LocalizationContext(locale: locale)
    }

    private var currentLanguageCache: SuggestedReplyCacheRecord? {
        suggestedReplyCacheRecords.first {
            $0.presentationLanguageIdentifier == localizationContext.languageIdentifier
        }
    }
}

private struct ChatImportReviewCard: View {
    let isProvisional: Bool
    let unknownSenderCount: Int
    let canMerge: Bool
    let provisionalIdentity: ProvisionalIdentityInterpretation?
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
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background {
                    Capsule(style: .continuous)
                        .fill(FrameReplyColor.primary)
                }
                .buttonStyle(SoftPressButtonStyle())

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
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(FrameReplyColor.secondaryContainer.opacity(0.42))
                        }
                }
                .buttonStyle(SoftPressButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(FrameReplyColor.surfaceContainerLow.opacity(0.42))
                }
                .overlay(alignment: .leading) {
                    if unknownSenderCount > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(FrameReplyColor.primary.opacity(0.56))
                            .frame(width: 3)
                            .padding(.vertical, 12)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(FrameReplyColor.outlineVariant.opacity(0.46), lineWidth: 1)
                }
        }
    }

    private var nudgeText: String {
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
        unknownSenderCount > 0 ? "person.crop.circle.badge.questionmark" : "tray.and.arrow.down"
    }

    private var primaryActionTitle: String {
        unknownSenderCount > 0 ? "Review" : "Keep"
    }

    private var primaryAction: () -> Void {
        unknownSenderCount > 0 ? onReviewSenders : onKeepAsNew
    }

    private var hasSecondaryActions: Bool {
        (isProvisional && provisionalIdentity != nil) || canMerge
    }
}
