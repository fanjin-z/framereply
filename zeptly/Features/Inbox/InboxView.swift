//
//  InboxView.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct InboxView: View {
    let isActive: Bool
    let onChatTap: (Chat) -> Void
    let onAvatarTap: (Chat) -> Void
    @State private var searchText = ""
    @State private var isReviewPresented = false
    @State private var chatPendingDeletion: Chat?
    @State private var isDeleteConfirmationPresented = false
    @State private var deleteErrorMessage: String?
    @Query(sort: \ChatRecord.updatedAt, order: .reverse) private var chatRecords: [ChatRecord]
    @Query(filter: #Predicate<ChatMessageRecord> { $0.senderKind == "unknown" })
    private var unknownSenderMessages: [ChatMessageRecord]

    private var chats: [Chat] {
        let allChats = chatRecords.map { Chat(record: $0) }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return allChats
        }

        return allChats.filter { chat in
            chat.name.localizedCaseInsensitiveContains(searchText)
                || chat.preview.localizedCaseInsensitiveContains(searchText)
                || chat.chipTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if reviewCount > 0 {
                    Button {
                        isReviewPresented = true
                    } label: {
                        Label(
                            "Review \(reviewCount) imported chat\(reviewCount == 1 ? "" : "s")",
                            systemImage: "exclamationmark.bubble.fill"
                        )
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(RezplyColor.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassPanel(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }

                SearchField(text: $searchText, isActive: isActive)
                    .padding(.top, reviewCount > 0 ? 4 : 14)

                VStack(spacing: 16) {
                    ForEach(chats) { chat in
                        ChatRow(
                            chat: chat,
                            onChatTap: {
                                onChatTap(chat)
                            },
                            onAvatarTap: {
                                onAvatarTap(chat)
                            },
                            onDeleteTap: {
                                chatPendingDeletion = chat
                                isDeleteConfirmationPresented = true
                            }
                        )
                    }

                    if chats.isEmpty {
                        EmptySearchState()
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 94)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $isReviewPresented) {
            ChatImportReviewSheet()
        }
        .confirmationDialog(
            "Delete chat with \(chatPendingDeletion?.name ?? "this person")?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                deletePendingChat()
            }
            Button("Cancel") {
                chatPendingDeletion = nil
            }
        } message: {
            Text("This permanently deletes this chat and its data. This can’t be undone.")
        }
        .alert("Could Not Delete Chat", isPresented: deleteErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "Try again.")
        }
    }

    private var reviewCount: Int {
        let provisionalIDs = Set(chatRecords.filter(\.isProvisional).map(\.id))
        let unknownIDs = Set(unknownSenderMessages.map(\.chatID))
        return provisionalIDs.union(unknownIDs).count
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

    private func deletePendingChat() {
        guard let chat = chatPendingDeletion else {
            return
        }

        do {
            try ChatRepository().deleteChat(id: chat.id)
            chatPendingDeletion = nil
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}
