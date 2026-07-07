//
//  ChatImportReviewSheet.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct ChatImportReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ChatRecord> { $0.isProvisional }) private var provisionalChats: [ChatRecord]
    @Query private var allChats: [ChatRecord]
    @Query(
        filter: #Predicate<ChatMessageRecord> { $0.senderKind == "unknown" },
        sort: \ChatMessageRecord.sortIndex
    ) private var unknownSenderMessages: [ChatMessageRecord]
    @State private var errorMessage: String?

    private var confirmedChats: [ChatRecord] {
        allChats.filter { !$0.isProvisional }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(provisionalChats) { chat in
                            ImportReviewCard(
                                chat: chat,
                                mergeCandidates: confirmedChats,
                                onConfirm: confirm,
                                onMerge: merge
                            )
                        }

                        ForEach(unknownSenderMessages) { message in
                            UnknownSenderReviewCard(
                                message: message,
                                chatName: allChats.first(where: { $0.id == message.chatID })?.name
                                    ?? "Imported chat",
                                onResolve: resolveSender
                            )
                        }

                        if provisionalChats.isEmpty && unknownSenderMessages.isEmpty {
                            ContentUnavailableView(
                                "Imports Reviewed",
                                systemImage: "checkmark.bubble",
                                description: Text("There are no imported chats or sender assignments waiting for review.")
                            )
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Review Imports")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        KeyboardDismissal.dismiss()
                        dismiss()
                    }
                }
            }
            .alert("Could Not Update Chat", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Try again.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func confirm(chatID: String, name: String) {
        KeyboardDismissal.dismiss()
        do {
            try ChatRepository().confirmProvisionalChat(chatID: chatID, name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func merge(provisionalChatID: String, targetChatID: String) {
        KeyboardDismissal.dismiss()
        do {
            try ChatRepository().mergeProvisionalChat(provisionalChatID, into: targetChatID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveSender(messageID: UUID, sender: AnalyzedMessageSender, participantName: String?) {
        do {
            try ChatRepository().resolveUnknownSender(
                messageID: messageID,
                as: sender,
                participantName: participantName
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UnknownSenderReviewCard: View {
    let message: ChatMessageRecord
    let chatName: String
    let onResolve: (UUID, AnalyzedMessageSender, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sender needs review", systemImage: "person.crop.circle.badge.questionmark")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RezplyColor.primary)

            Text(chatName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)

            Text(message.text)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Me") {
                    onResolve(message.id, .user, nil)
                }
                .buttonStyle(.borderedProminent)

                Button("Contact") {
                    onResolve(message.id, .contact, nil)
                }
                .buttonStyle(.bordered)

                Button(message.senderName ?? "Participant") {
                    onResolve(message.id, .other, message.senderName)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 22)
    }
}

private struct ImportReviewCard: View {
    let chat: ChatRecord
    let mergeCandidates: [ChatRecord]
    let onConfirm: (String, String) -> Void
    let onMerge: (String, String) -> Void

    @State private var name: String

    init(
        chat: ChatRecord,
        mergeCandidates: [ChatRecord],
        onConfirm: @escaping (String, String) -> Void,
        onMerge: @escaping (String, String) -> Void
    ) {
        self.chat = chat
        self.mergeCandidates = mergeCandidates
        self.onConfirm = onConfirm
        self.onMerge = onMerge
        _name = State(initialValue: chat.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AvatarMark(
                    initials: chat.initials,
                    symbolName: chat.avatarSymbol,
                    colors: [RezplyColor.peach, RezplyColor.primaryContainer],
                    imageData: chat.avatarData,
                    size: 38
                )
                Label("Needs review", systemImage: "exclamationmark.bubble.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.primary)
            }

            TextField("Chat name", text: $name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { KeyboardDismissal.dismiss() }

            Text(chat.preview)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)
                .lineLimit(3)

            HStack {
                Button("Keep as New") {
                    onConfirm(chat.id, name)
                }
                .buttonStyle(.borderedProminent)

                if !mergeCandidates.isEmpty {
                    Menu("Merge Into…") {
                        ForEach(mergeCandidates) { candidate in
                            Button(candidate.name) {
                                onMerge(chat.id, candidate.id)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 22)
    }
}
