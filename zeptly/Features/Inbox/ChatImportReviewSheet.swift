//
//  ChatImportReviewSheet.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct ChatImportReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allChats: [ChatRecord]
    @Query private var unknownSenderMessages: [ChatMessageRecord]
    @State private var errorMessage: String?

    private let chatID: String?
    private let onMerged: ((String) -> Void)?

    init(chatID: String? = nil, onMerged: ((String) -> Void)? = nil) {
        self.chatID = chatID
        self.onMerged = onMerged
        if let chatID {
            let scopedChatID = chatID
            _unknownSenderMessages = Query(
                filter: #Predicate<ChatMessageRecord> {
                    $0.senderKind == "unknown" && $0.chatID == scopedChatID
                },
                sort: \ChatMessageRecord.sortIndex
            )
        } else {
            _unknownSenderMessages = Query(
                filter: #Predicate<ChatMessageRecord> { $0.senderKind == "unknown" },
                sort: \ChatMessageRecord.sortIndex
            )
        }
        _allChats = Query()
    }

    private var provisionalChats: [ChatRecord] {
        allChats.filter { chat in
            chat.requiresImportIdentityReview && (chatID == nil || chat.id == chatID)
        }
    }

    private var confirmedChats: [ChatRecord] {
        allChats.filter { !$0.requiresImportIdentityReview }
    }

    private var showsSectionHeaders: Bool {
        !provisionalChats.isEmpty && !unknownSenderMessages.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !provisionalChats.isEmpty {
                            if showsSectionHeaders {
                                ImportReviewSectionHeader(title: "Imported chats")
                            }

                            VStack(spacing: 10) {
                                ForEach(provisionalChats) { chat in
                                    ImportReviewCard(
                                        chat: chat,
                                        mergeCandidates: confirmedChats,
                                        onConfirm: confirm,
                                        onMerge: merge
                                    )
                                }
                            }
                        }

                        if !unknownSenderMessages.isEmpty {
                            if showsSectionHeaders {
                                ImportReviewSectionHeader(title: "Sender labels")
                                    .padding(.top, 4)
                            }

                            VStack(spacing: 10) {
                                ForEach(unknownSenderMessages) { message in
                                    UnknownSenderReviewCard(
                                        message: message,
                                        chatName:
                                            allChats.first(where: { $0.id == message.chatID })?.name
                                            ?? "Imported chat",
                                        onResolve: resolveSender
                                    )
                                }
                            }
                        }

                        if provisionalChats.isEmpty && unknownSenderMessages.isEmpty {
                            ContentUnavailableView(
                                "Imports Reviewed",
                                systemImage: "checkmark.bubble",
                                description: Text("All imports are reviewed.")
                            )
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle(chatID == nil ? "Review Imports" : "Review Import")
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
            if onMerged != nil {
                dismiss()
                onMerged?(targetChatID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveSender(
        messageID: UUID, sender: AnalyzedMessageSender, participantName: String?
    ) {
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

private struct ImportReviewSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(RezplyColor.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UnknownSenderReviewCard: View {
    let message: ChatMessageRecord
    let chatName: String
    let onResolve: (UUID, AnalyzedMessageSender, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Who sent this?")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)

                Spacer(minLength: 8)

                Text(chatName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Text(message.text)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)
                .lineLimit(2)

            HStack(spacing: 8) {
                SenderChoiceChip("Me") {
                    onResolve(message.id, .user, nil)
                }

                SenderChoiceChip("Other Participant") {
                    onResolve(message.id, .otherParticipant, nil)
                }

                SenderChoiceChip(message.senderName ?? "Participant") {
                    onResolve(message.id, .groupParticipant, message.senderName)
                }
            }
        }
        .padding(14)
        .quietReviewPanel(accented: true)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                AvatarMark(
                    initials: chat.initials,
                    symbolName: chat.avatarSymbol,
                    colors: [RezplyColor.peach, RezplyColor.primaryContainer],
                    imageData: chat.avatarData,
                    size: 34
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Imported chat")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurfaceVariant)

                    TextField("Chat name", text: $name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)
                        .submitLabel(.done)
                        .onSubmit { KeyboardDismissal.dismiss() }
                }
            }

            Text(chat.preview)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button {
                    onConfirm(chat.id, name)
                } label: {
                    Text("Keep")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            Capsule(style: .continuous)
                                .fill(RezplyColor.primary)
                        }
                }
                .buttonStyle(SoftPressButtonStyle())

                if !mergeCandidates.isEmpty {
                    Menu {
                        ForEach(mergeCandidates) { candidate in
                            Button(candidate.name) {
                                onMerge(chat.id, candidate.id)
                            }
                        }
                    } label: {
                        Text("Merge into...")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(RezplyColor.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(RezplyColor.secondaryContainer.opacity(0.46))
                            }
                    }
                    .buttonStyle(SoftPressButtonStyle())
                }
            }
        }
        .padding(14)
        .quietReviewPanel()
    }
}

private struct SenderChoiceChip: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RezplyColor.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    Capsule(style: .continuous)
                        .fill(RezplyColor.secondaryContainer.opacity(0.46))
                }
        }
        .buttonStyle(SoftPressButtonStyle())
    }
}

extension View {
    fileprivate func quietReviewPanel(accented: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(RezplyColor.surfaceContainerLow.opacity(0.42))
                }
                .overlay(alignment: .leading) {
                    if accented {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(RezplyColor.primary.opacity(0.56))
                            .frame(width: 3)
                            .padding(.vertical, 12)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(RezplyColor.outlineVariant.opacity(0.46), lineWidth: 1)
                }
        }
    }
}
