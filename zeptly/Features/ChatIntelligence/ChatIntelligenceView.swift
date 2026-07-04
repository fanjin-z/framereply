//
//  ChatIntelligenceView.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct ChatIntelligenceView: View {
    let chat: Chat
    let intelligence: ChatIntelligence
    @ObservedObject var providerStore: ProviderStore
    let onContactTap: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isHistoryPresented = false
    @State private var isContextPresented = false
    @State private var isScreenshotAttached = false
    @State private var contextNote = ""
    @State private var copiedReplyID: UUID?
    @State private var isDeleteConfirmationPresented = false
    @State private var deleteErrorMessage: String?
    @Query private var messageRecords: [ChatMessageRecord]
    @Query private var contactContextRecords: [ContactContextRecord]
    @StateObject private var suggestedRepliesModel: SuggestedRepliesViewModel

    init(
        chat: Chat,
        intelligence: ChatIntelligence,
        providerStore: ProviderStore,
        onContactTap: @escaping () -> Void
    ) {
        self.chat = chat
        self.intelligence = intelligence
        self.providerStore = providerStore
        self.onContactTap = onContactTap
        let chatID = chat.id
        _messageRecords = Query(
            filter: #Predicate<ChatMessageRecord> { $0.chatID == chatID },
            sort: \ChatMessageRecord.sortIndex
        )
        _contactContextRecords = Query(
            filter: #Predicate<ContactContextRecord> { $0.chatID == chatID }
        )
        _suggestedRepliesModel = StateObject(
            wrappedValue: SuggestedRepliesViewModel(
                chatID: chatID,
                coordinator: SuggestedRepliesCoordinator(providerStore: providerStore)
            )
        )
    }

    private var messages: [ChatMessage] {
        messageRecords.map { ChatMessage(record: $0) }
    }

    private var latestMessages: [ChatMessage] {
        Array(messages.suffix(3))
    }

    private var replyGenerationKey: Int {
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
            hasher.combine(context.relationshipNotes)
            hasher.combine(context.keyFactsJSON)
            hasher.combine(context.currentInteractionGoal)
            hasher.combine(context.preferredPersona)
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
                        onDeleteTap: {
                            isDeleteConfirmationPresented = true
                        }
                    )

                    ChatContextChipPanel(chips: intelligence.contextChips)

                    RecentChatSection(
                        messages: latestMessages,
                        onHistoryTap: {
                            isHistoryPresented = true
                        }
                    )

                    ChatCaptureControls(
                        isScreenshotAttached: isScreenshotAttached,
                        hasContextNote: !contextNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        onAttachTap: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                isScreenshotAttached.toggle()
                            }
                        },
                        onContextTap: {
                            isContextPresented = true
                        }
                    )

                    SuggestedRepliesSection(
                        replies: suggestedRepliesModel.replies,
                        copiedReplyID: copiedReplyID,
                        isLoading: suggestedRepliesModel.isLoading,
                        errorMessage: suggestedRepliesModel.errorMessage,
                        onCopy: copyReply,
                        onRetry: regenerateReplies,
                        onRegenerate: regenerateReplies
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
        .task(id: replyGenerationKey) {
            await suggestedRepliesModel.load()
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

    private func copyReply(_ reply: SuggestedReply) {
        ClipboardWriter.copy(reply.text)

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            copiedReplyID = reply.id
        }
    }

    private func regenerateReplies() {
        Task {
            await suggestedRepliesModel.load(force: true, discardExisting: false)
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
}
