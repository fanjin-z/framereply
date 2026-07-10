//
//  ChatIntelligenceView.swift
//  zeptly
//

import SwiftData
import PhotosUI
import SwiftUI

struct ChatIntelligenceView: View {
    let chat: Chat
    let intelligence: ChatIntelligence
    @ObservedObject var providerStore: ProviderStore
    let onContactTap: () -> Void
    let onMergedIntoChat: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isHistoryPresented = false
    @State private var isContextPresented = false
    @State private var isReviewPresented = false
    @State private var isRenamePresented = false
    @State private var renameDraft = ""
    @State private var isMergeConfirmationPresented = false
    @State private var actionErrorMessage: String?
    @State private var selectedScreenshotItems: [PhotosPickerItem] = []
    @State private var photoLoadErrorMessage: String?
    @State private var contextNote = ""
    @State private var lastRecordedContextNote = ""
    @State private var copiedReplyID: UUID?
    @State private var isDeleteConfirmationPresented = false
    @State private var deleteErrorMessage: String?
    @Query private var currentChatRecords: [ChatRecord]
    @Query private var messageRecords: [ChatMessageRecord]
    @Query private var contactContextRecords: [ContactContextRecord]
    @Query private var contactMemoryRecords: [ContactMemoryRecord]
    @Query private var suggestedReplyCacheRecords: [SuggestedReplyCacheRecord]
    @Query private var mergeCandidateRecords: [ChatRecord]
    @StateObject private var suggestedRepliesModel: SuggestedRepliesViewModel
    @StateObject private var importModel: InAppScreenshotImportViewModel

    init(
        chat: Chat,
        intelligence: ChatIntelligence,
        providerStore: ProviderStore,
        onContactTap: @escaping () -> Void,
        onMergedIntoChat: @escaping (String) -> Void
    ) {
        self.chat = chat
        self.intelligence = intelligence
        self.providerStore = providerStore
        self.onContactTap = onContactTap
        self.onMergedIntoChat = onMergedIntoChat
        let chatID = chat.id
        _currentChatRecords = Query(
            filter: #Predicate<ChatRecord> { $0.id == chatID }
        )
        _messageRecords = Query(
            filter: #Predicate<ChatMessageRecord> { $0.chatID == chatID },
            sort: \ChatMessageRecord.sortIndex
        )
        _contactContextRecords = Query(
            filter: #Predicate<ContactContextRecord> { $0.chatID == chatID }
        )
        _contactMemoryRecords = Query(
            filter: #Predicate<ContactMemoryRecord> { $0.chatID == chatID },
            sort: \ContactMemoryRecord.createdAt
        )
        _suggestedReplyCacheRecords = Query(
            filter: #Predicate<SuggestedReplyCacheRecord> { $0.chatID == chatID }
        )
        _mergeCandidateRecords = Query(
            filter: #Predicate<ChatRecord> { $0.id != chatID },
            sort: \ChatRecord.name
        )
        _suggestedRepliesModel = StateObject(
            wrappedValue: SuggestedRepliesViewModel(
                chatID: chatID,
                coordinator: SuggestedRepliesCoordinator(providerStore: providerStore)
            )
        )
        _importModel = StateObject(
            wrappedValue: InAppScreenshotImportViewModel(providerStore: providerStore)
        )
    }

    private var messages: [ChatMessage] {
        messageRecords.map { ChatMessage(record: $0) }
    }

    private var latestMessages: [ChatMessage] {
        Array(messages.suffix(3))
    }

    private var currentChatRecord: ChatRecord? {
        currentChatRecords.first
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
        if let context = contactContextRecords.first {
            hasher.combine(context.relationshipSubtitle)
            hasher.combine(context.currentInteractionGoal)
            hasher.combine(context.personaID)
            hasher.combine(context.personaAssignedAt)
        }
        for memory in contactMemoryRecords
        where memory.status == ContactMemoryStatus.active.rawValue {
            hasher.combine(memory.id)
            hasher.combine(memory.text)
            hasher.combine(memory.origin)
            hasher.combine(memory.certainty)
            hasher.combine(memory.status)
        }
        if let cache = suggestedReplyCacheRecords.first {
            hasher.combine(cache.inputFingerprint)
            hasher.combine(cache.repliesJSON)
            hasher.combine(cache.promptVersion)
            hasher.combine(cache.generatedAt)
        }
        hasher.combine(providerStore.activeProvider?.platform.rawValue)
        hasher.combine(providerStore.activeProvider?.model.rawValue)
        return hasher.finalize()
    }

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ChatIntelligenceTopBar(
                        chat: chat,
                        onBackTap: {
                            dismiss()
                        },
                        onContactTap: onContactTap,
                        onRenameTap: {
                            renameDraft = chat.name
                            isRenamePresented = true
                        },
                        onDeleteTap: {
                            isDeleteConfirmationPresented = true
                        }
                    )

                    if shouldShowImportReviewCard {
                        ChatImportReviewCard(
                            chatName: currentChatRecord?.name ?? chat.name,
                            isProvisional: isCurrentChatProvisional,
                            unknownSenderCount: unknownSenderCount,
                            canMerge: !mergeCandidates.isEmpty,
                            onKeepAsNew: confirmCurrentChat,
                            onMergeTap: {
                                isMergeConfirmationPresented = true
                            },
                            onReviewSenders: {
                                isReviewPresented = true
                            }
                        )
                    }

                    RecentChatSection(
                        messages: latestMessages,
                        onHistoryTap: {
                            isHistoryPresented = true
                        }
                    )

                    ChatCaptureControls(
                        screenshotSelection: $selectedScreenshotItems,
                        isImporting: importModel.isLoading,
                        hasContextNote: !contextNote.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty,
                        onContextTap: {
                            isContextPresented = true
                        }
                    )

                    if importModel.isLoading {
                        ScreenshotImportStatusCard(
                            symbolName: "sparkles",
                            message: "Analyzing selected screenshots…",
                            isLoading: true
                        )
                    } else if let importStatusMessage {
                        ScreenshotImportStatusCard(
                            symbolName: importStatusSymbolName,
                            message: importStatusMessage,
                            isLoading: false
                        )
                    }

                    SuggestedRepliesSection(
                        replies: suggestedRepliesModel.replies,
                        copiedReplyID: copiedReplyID,
                        isLoading: suggestedRepliesModel.isLoading,
                        errorMessage: suggestedRepliesModel.errorMessage,
                        onCopy: copyReply,
                        onRetry: regenerateReplies,
                        onGenerate: regenerateReplies
                    )

                    SuggestedActionCard(action: intelligence.suggestedAction)

                    ChatReasoningCard(reasoning: intelligence.reasoning)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .interactiveSwipeBackEnabled()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isHistoryPresented) {
            ChatHistorySheet(chat: chat)
        }
        .sheet(isPresented: $isContextPresented) {
            AddChatContextSheet(note: $contextNote)
        }
        .sheet(isPresented: $isReviewPresented) {
            ChatImportReviewSheet(chatID: chat.id, onMerged: onMergedIntoChat)
        }
        .alert("Rename Chat", isPresented: $isRenamePresented) {
            TextField("Chat name", text: $renameDraft)
            Button("Save") {
                renameChat()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a clear name for this chat.")
        }
        .confirmationDialog(
            "Merge Imported Chat",
            isPresented: $isMergeConfirmationPresented,
            titleVisibility: .visible
        ) {
            ForEach(mergeCandidates) { candidate in
                Button("Merge Into \(candidate.name)") {
                    mergeChat(into: candidate.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move this imported chat into an existing chat. This can’t be undone.")
        }
        .confirmationDialog(
            "Delete chat with \(chat.name)?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                deleteChat()
            }
            Button("Cancel") {
                isDeleteConfirmationPresented = false
            }
        } message: {
            Text("This permanently deletes this chat and its data. This can’t be undone.")
        }
        .alert("Could Not Delete Chat", isPresented: deleteErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "Try again.")
        }
        .alert("Could Not Update Chat", isPresented: actionErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "Try again.")
        }
        .task(id: replyCacheKey) {
            suggestedRepliesModel.loadCached()
        }
        .task(id: shouldShowImportReviewCard) {
            recordReviewExposureIfNeeded()
        }
        .onChange(of: selectedScreenshotItems) { _, items in
            Task {
                await importSelectedScreenshots(items)
            }
        }
        .onChange(of: isContextPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented {
                recordContextNoteActionIfNeeded()
            }
        }
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorMessage = nil
                }
            }
        )
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
                return "\(result.message) Suggested replies could not be generated: \(replyErrorMessage)"
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

    private func importSelectedScreenshots(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        defer { selectedScreenshotItems = [] }
        photoLoadErrorMessage = nil

        do {
            let imageDataList = try await ChatScreenshotPhotoLoader.loadData(from: items)
            let draftingInput = contextNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if let result = await importModel.importScreenshots(
                imageDataList,
                draftingInput: draftingInput.isEmpty ? nil : draftingInput
            ), result.chatID == chat.id {
                suggestedRepliesModel.loadCached()
                recordMeaningfulReviewAction()
            }
        } catch {
            photoLoadErrorMessage = error.localizedDescription
        }
    }

    private func copyReply(_ reply: SuggestedReply) {
        ClipboardWriter.copy(reply.text)

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            copiedReplyID = reply.id
        }
        recordMeaningfulReviewAction()
    }

    private func regenerateReplies() {
        Task {
            if await suggestedRepliesModel.regenerate() {
                recordMeaningfulReviewAction()
            }
        }
    }

    private func renameChat() {
        do {
            try ChatRepository().renameChat(id: chat.id, name: renameDraft)
            recordMeaningfulReviewAction()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func confirmCurrentChat() {
        do {
            try ChatRepository().confirmProvisionalChat(
                chatID: chat.id,
                name: currentChatRecord?.name ?? chat.name
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

    private func deleteChat() {
        do {
            try ChatRepository().deleteChat(id: chat.id)
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
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

    private func recordContextNoteActionIfNeeded() {
        let trimmedNote = contextNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty, trimmedNote != lastRecordedContextNote else {
            return
        }
        lastRecordedContextNote = trimmedNote
        recordMeaningfulReviewAction()
    }
}

private struct ChatImportReviewCard: View {
    let chatName: String
    let isProvisional: Bool
    let unknownSenderCount: Int
    let canMerge: Bool
    let onKeepAsNew: () -> Void
    let onMergeTap: () -> Void
    let onReviewSenders: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Review import", systemImage: "exclamationmark.bubble.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RezplyColor.primary)

            Text(reviewMessage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if isProvisional {
                    Button("Keep as New") {
                        onKeepAsNew()
                    }
                    .buttonStyle(.borderedProminent)

                    if canMerge {
                        Button("Merge Into...") {
                            onMergeTap()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if unknownSenderCount > 0 {
                    if isProvisional {
                        Button("Review Senders") {
                            onReviewSenders()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Review Senders") {
                            onReviewSenders()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }

    private var reviewMessage: String {
        if isProvisional && unknownSenderCount > 0 {
            return "\(chatName) is an imported chat, and \(unknownSenderCount) sender assignment\(unknownSenderCount == 1 ? "" : "s") need review."
        }
        if isProvisional {
            return "\(chatName) is an imported chat. Keep it as a new chat or merge it into an existing one."
        }
        return "\(unknownSenderCount) sender assignment\(unknownSenderCount == 1 ? "" : "s") need review."
    }
}

private struct ScreenshotImportStatusCard: View {
    let symbolName: String
    let message: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RezplyColor.primary)
            }
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18)
    }
}
