//
//  ChatDetailsView.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct ChatDetailsView: View {
    let chat: Chat
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var chatRecords: [ChatRecord]
    @Query private var memoryRecords: [ChatMemoryRecord]
    @Query private var replyCaches: [SuggestedReplyCacheRecord]
    @State private var isRenamePresented = false
    @State private var renameDraft = ""
    @State private var isDeleteConfirmationPresented = false
    @State private var errorMessage: String?

    init(chat: Chat, onDeleted: @escaping () -> Void) {
        self.chat = chat
        self.onDeleted = onDeleted
        let chatID = chat.id
        _chatRecords = Query(filter: #Predicate<ChatRecord> { $0.id == chatID })
        _memoryRecords = Query(
            filter: #Predicate<ChatMemoryRecord> { $0.chatID == chatID },
            sort: \ChatMemoryRecord.createdAt
        )
        _replyCaches = Query(
            filter: #Predicate<SuggestedReplyCacheRecord> { $0.chatID == chatID }
        )
    }

    @MainActor private var displayedChat: Chat {
        chatRecords.first.map(Chat.init(record:)) ?? chat
    }

    private var rationale: String {
        replyCaches.first?.strategyRationale.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    topBar

                    HStack(spacing: 16) {
                        AvatarMark(
                            initials: displayedChat.initials,
                            symbolName: displayedChat.avatarSymbol,
                            colors: displayedChat.gradient,
                            imageData: displayedChat.avatarData,
                            size: 58
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(displayedChat.name)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(RezplyColor.onSurface)
                                .lineLimit(2)

                            Button("Rename Chat") {
                                renameDraft = displayedChat.name
                                isRenamePresented = true
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(RezplyColor.primary)
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(20)
                    .glassPanel(cornerRadius: 26)

                    if let cache = replyCaches.first, !rationale.isEmpty {
                        StrategyRationaleCard(
                            strategyRationale: rationale,
                            generatedAt: cache.generatedAt
                        )
                    }

                    ChatMemoryCard(
                        chatID: chat.id,
                        chatName: displayedChat.name,
                        memoryRecords: memoryRecords
                    )

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Label("Delete Chat", systemImage: "trash")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .interactiveSwipeBackEnabled()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
        .alert("Could Not Update Chat", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                KeyboardDismissal.dismiss()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(RezplyColor.primary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Back to chat assistant")

            Text("Chat Details")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)

            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func renameChat() {
        do {
            try ChatRepository().renameChat(id: chat.id, name: renameDraft)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteChat() {
        do {
            try ChatRepository().deleteChat(id: chat.id)
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
