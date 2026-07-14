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
    @Query private var chatContextRecords: [ChatContextRecord]
    @Query private var selfAliasRecords: [ChatSelfAliasRecord]
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
        _selfAliasRecords = Query(
            filter: #Predicate<ChatSelfAliasRecord> { $0.chatID == chatID },
            sort: \ChatSelfAliasRecord.createdAt
        )
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

    private var isDirectChat: Bool {
        chatRecords.first?.conversationKind == .direct
    }

    private var participantAliases: [ChatParticipantAlias] {
        chatContextRecords.first?.participantAliases ?? []
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

                            Button(isDirectChat ? "Edit Names" : "Rename Chat") {
                                if isDirectChat {
                                    isEditNamesPresented = true
                                } else {
                                    renameDraft = displayedChat.name
                                    isRenamePresented = true
                                }
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

                    if !selfAliasRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("You appear as", systemImage: "person.text.rectangle")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(RezplyColor.onSurface)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(selfAliasRecords) { alias in
                                    Text(alias.displayLabel)
                                        .font(
                                            .system(size: 14, weight: .semibold, design: .rounded)
                                        )
                                        .foregroundStyle(RezplyColor.onSurface)
                                        .padding(.horizontal, 12)
                                        .frame(height: 34)
                                        .background {
                                            Capsule(style: .continuous)
                                                .fill(RezplyColor.secondaryContainer.opacity(0.48))
                                        }
                                }
                            }

                            Text("Zeptly uses these names only for future imports into this chat.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(RezplyColor.onSurfaceVariant)

                            Button("Forget imported identity", role: .destructive) {
                                isForgetIdentityConfirmationPresented = true
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))
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
            "Forget imported identity?",
            isPresented: $isForgetIdentityConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Forget Identity", role: .destructive, action: forgetImportedIdentity)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Future imports may ask which sender is you again. Existing messages won’t change.")
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
                    Text("This is the name shown throughout Zeptly.")
                }

                Section {
                    ForEach(aliases) { alias in
                        HStack(spacing: 12) {
                            Text(alias.displayLabel)
                                .foregroundStyle(RezplyColor.onSurface)

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
                                    .foregroundStyle(RezplyColor.primary)
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
                            .disabled(ChatParticipantAlias.displayLabel(newAlias) == nil)
                    }
                } header: {
                    Text("Also known as")
                } footer: {
                    Text(
                        "Zeptly uses these names to recognize this person in screenshots and pasted transcripts. Removing one may make a future import require review; existing messages won’t change."
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
                        .disabled(ChatParticipantAlias.displayLabel(displayName) == nil)
                }
            }
            .alert("Could Not Update Names", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Try again.")
            }
        }
    }

    private func addAlias() {
        guard let label = ChatParticipantAlias.displayLabel(newAlias),
            let key = ChatParticipantAlias.normalizedKey(label),
            key != ChatParticipantAlias.normalizedKey(displayName),
            key != ChatParticipantAlias.normalizedKey("Imported Chat"),
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
        if let formerLabel = ChatParticipantAlias.displayLabel(formerDisplayName),
            let formerKey = ChatParticipantAlias.normalizedKey(formerLabel),
            formerKey != ChatParticipantAlias.normalizedKey("Imported Chat"),
            formerKey != ChatParticipantAlias.normalizedKey(displayName),
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
