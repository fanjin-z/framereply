//
//  ChatDetailsView.swift
//  FrameReply
//

import SwiftData
import SwiftUI

struct ChatDetailsView: View {
    let chat: Chat
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var chatRecords: [ChatRecord]
    @Query private var chatContextRecords: [ChatContextRecord]
    @Query private var allChatContextRecords: [ChatContextRecord]
    @Query private var messageRecords: [ChatMessageRecord]
    @Query private var memoryRecords: [ChatMemoryRecord]
    @Query private var replyCaches: [SuggestedReplyCacheRecord]
    @State private var isRenamePresented = false
    @State private var renameDraft = ""
    @State private var isEditNamesPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isForgetIdentityConfirmationPresented = false
    @State private var errorMessage: String?

    init(chat: Chat, onDeleted: @escaping () -> Void) {
        self.chat = chat
        self.onDeleted = onDeleted
        let chatID = chat.id
        _chatRecords = Query(filter: #Predicate<ChatRecord> { $0.id == chatID })
        _chatContextRecords = Query(
            filter: #Predicate<ChatContextRecord> { $0.chatID == chatID }
        )
        _allChatContextRecords = Query()
        _messageRecords = Query(
            filter: #Predicate<ChatMessageRecord> { $0.chatID == chatID },
            sort: \ChatMessageRecord.sortIndex
        )
        _memoryRecords = Query(
            filter: #Predicate<ChatMemoryRecord> { $0.chatID == chatID },
            sort: \ChatMemoryRecord.createdAt
        )
        _replyCaches = Query(
            filter: #Predicate<SuggestedReplyCacheRecord> { $0.chatID == chatID }
        )
    }

    private var provisionalIdentity: ProvisionalIdentityInterpretation? {
        ProvisionalIdentityResolver.resolve(
            chat: chatRecords.first,
            messages: messageRecords,
            previouslyUsedSelfAliasLabels:
                ProvisionalIdentityResolver.previouslyUsedSelfAliasLabels(
                    in: allChatContextRecords
                )
        )
    }

    @MainActor private var displayedChat: Chat {
        chatRecords.first.map {
            Chat(record: $0, provisionalIdentity: provisionalIdentity)
        } ?? chat
    }

    private var rationale: String {
        replyCaches.first?.strategyRationale.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var isDirectChat: Bool {
        chatRecords.first?.conversationKind == .direct
    }

    private var participantAliases: [ChatParticipantAlias] {
        chatContextRecords.first?.participantAliases ?? []
    }

    private var selfAliasRecords: [SelfAliasRecord] {
        (chatContextRecords.first?.selfAliases ?? []).sorted {
            $0.displayLabel.localizedStandardCompare($1.displayLabel) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 16) {
                        AvatarMark(
                            initials: displayedChat.initials,
                            symbolName: displayedChat.avatarSymbol,
                            colors: displayedChat.gradient,
                            size: 58
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(displayedChat.name)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurface)
                                .lineLimit(2)

                            if let provisionalIdentity {
                                Label(
                                    "Pending review · Assuming you are \(provisionalIdentity.selfDisplayLabel)",
                                    systemImage: "person.crop.circle.badge.questionmark"
                                )
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                                .lineLimit(2)
                            }

                            Button(
                                isDirectChat
                                    ? LocalizedStringResource("Edit Names")
                                    : LocalizedStringResource("Rename Chat")
                            ) {
                                if isDirectChat {
                                    isEditNamesPresented = true
                                } else {
                                    renameDraft = displayedChat.name
                                    isRenamePresented = true
                                }
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(FrameReplyColor.primary)
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(20)
                    .glassPanel(cornerRadius: 26)

                    if !rationale.isEmpty {
                        StrategyRationaleCard(strategyRationale: rationale)
                    }

                    if !selfAliasRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("You appear as", systemImage: "person.text.rectangle")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurface)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(selfAliasRecords) { alias in
                                    Text(alias.displayLabel)
                                        .font(
                                            .system(size: 14, weight: .semibold, design: .rounded)
                                        )
                                        .foregroundStyle(FrameReplyColor.onSurface)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 34)
                                        .background {
                                            Capsule(style: .continuous)
                                                .fill(
                                                    FrameReplyColor.secondaryContainer.opacity(0.48)
                                                )
                                        }
                                }
                            }

                            Text(
                                "These names help recognize you in this chat and may be suggested for other imports."
                            )
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                            Button("Forget for this chat", role: .destructive) {
                                isForgetIdentityConfirmationPresented = true
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))

                            NavigationLink(value: FrameReplyRoute.namesAndUsernames) {
                                Text("Manage Names & Usernames")
                                    .font(
                                        .system(size: 13, weight: .bold, design: .rounded)
                                    )
                            }
                        }
                        .padding(20)
                        .glassPanel(cornerRadius: 26)
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
                            .frame(minHeight: 50)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .interactiveSwipeBackEnabled()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditNamesPresented) {
            EditParticipantNamesSheet(
                chatID: chat.id,
                displayName: displayedChat.name,
                aliases: participantAliases
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
            "Forget these names for this chat?",
            isPresented: $isForgetIdentityConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Forget for This Chat", role: .destructive, action: forgetImportedIdentity)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Future imports into this chat may ask which sender is you again. Your saved names and existing messages won’t change."
            )
        }
        .alert("Could Not Update Chat", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? String(localized: AppStrings.Common.tryAgain))
        }
    }

    private var topBar: some View {
        FrameReplyTopBar {
            HStack(spacing: 12) {
                FrameReplyTopBarBackButton(
                    accessibilityLabel: "Back to chat assistant"
                ) {
                    KeyboardDismissal.dismiss()
                    dismiss()
                }

                Text("Chat Details")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)

                Spacer()
            }
            .accessibilityIdentifier("chat-details-top-bar")
        }
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

    private func forgetImportedIdentity() {
        do {
            try ChatRepository().forgetImportedSelfLabels(chatID: chat.id)
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

private struct EditParticipantNamesSheet: View {
    let chatID: String

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var aliases: [ChatParticipantAlias]
    @State private var newAlias = ""
    @State private var errorMessage: String?

    init(chatID: String, displayName: String, aliases: [ChatParticipantAlias]) {
        self.chatID = chatID
        _displayName = State(initialValue: displayName)
        _aliases = State(initialValue: aliases)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                } header: {
                    Text("Display name")
                } footer: {
                    Text("This is the name shown throughout FrameReply.")
                }

                Section {
                    ForEach(aliases) { alias in
                        HStack(spacing: 12) {
                            Text(alias.displayLabel)
                                .foregroundStyle(FrameReplyColor.onSurface)

                            Spacer()

                            Menu {
                                Button("Use as Display Name") {
                                    promote(alias)
                                }
                                Button("Remove Name", role: .destructive) {
                                    aliases.removeAll { $0.id == alias.id }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(FrameReplyColor.primary)
                            }
                            .accessibilityLabel("Options for \(alias.displayLabel)")
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("Name or username", text: $newAlias)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit(addAlias)

                        Button("Add", action: addAlias)
                            .disabled(IdentityLabelPolicy.displayLabel(newAlias) == nil)
                    }
                } header: {
                    Text("Also known as")
                } footer: {
                    Text(
                        "FrameReply uses these names to recognize this person in screenshots and pasted transcripts. Removing one may make a future import require review; existing messages won’t change."
                    )
                }
            }
            .navigationTitle("Edit Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(IdentityLabelPolicy.displayLabel(displayName) == nil)
                }
            }
            .alert("Could Not Update Names", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: errorMessage ?? String(localized: AppStrings.Common.tryAgain))
            }
        }
    }

    private func addAlias() {
        guard let label = IdentityLabelPolicy.displayLabel(newAlias),
            let key = IdentityLabelPolicy.normalizedKey(label),
            key != IdentityLabelPolicy.normalizedKey(displayName),
            !aliases.contains(where: { $0.normalizedLabel == key })
        else {
            newAlias = ""
            return
        }
        aliases.append(ChatParticipantAlias(displayLabel: label))
        newAlias = ""
    }

    private func promote(_ alias: ChatParticipantAlias) {
        let formerDisplayName = displayName
        displayName = alias.displayLabel
        aliases.removeAll { $0.id == alias.id }
        if let formerLabel = IdentityLabelPolicy.displayLabel(formerDisplayName),
            let formerKey = IdentityLabelPolicy.normalizedKey(formerLabel),
            formerKey != IdentityLabelPolicy.normalizedKey(displayName),
            !aliases.contains(where: { $0.normalizedLabel == formerKey })
        {
            aliases.append(ChatParticipantAlias(displayLabel: formerLabel))
        }
    }

    private func save() {
        do {
            try ChatRepository().updateParticipantNames(
                chatID: chatID,
                displayName: displayName,
                aliases: aliases
            )
            dismiss()
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
