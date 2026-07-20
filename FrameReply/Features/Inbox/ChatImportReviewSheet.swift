//
//  ChatImportReviewSheet.swift
//  FrameReply
//

import SwiftData
import SwiftUI

struct ChatImportReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allChats: [ChatRecord]
    @Query private var allChatContexts: [ChatContextRecord]
    @Query private var unknownSenderMessages: [ChatMessageRecord]
    @State private var errorMessage: String?
    @State private var individuallyReviewedChatIDs: Set<String> = []

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
        _allChatContexts = Query()
    }

    private var provisionalChats: [ChatRecord] {
        allChats.filter { chat in
            chat.requiresImportIdentityReview && (chatID == nil || chat.id == chatID)
        }
    }

    private var confirmedChats: [ChatRecord] {
        allChats.filter { !$0.requiresImportIdentityReview }
    }

    private var participantReviewGroups: [ParticipantReviewGroup] {
        let labelGroups = UnknownSenderLabelGroup.make(from: unknownSenderMessages)
        var chatOrder: [String] = []
        var grouped: [String: [UnknownSenderLabelGroup]] = [:]
        for group in labelGroups {
            if grouped[group.chatID] == nil {
                chatOrder.append(group.chatID)
            }
            grouped[group.chatID, default: []].append(group)
        }
        return chatOrder.compactMap { id in
            guard let groups = grouped[id], !groups.isEmpty else { return nil }
            return ParticipantReviewGroup(
                chatID: id,
                chatName: ChatPresentation.title(
                    for: allChats.first(where: { $0.id == id })
                ),
                groups: groups
            )
        }
    }

    private var visibleParticipantReviewGroups: [ParticipantReviewGroup] {
        participantReviewGroups.filter { !individuallyReviewedChatIDs.contains($0.chatID) }
    }

    private var individualMessages: [ChatMessageRecord] {
        unknownSenderMessages.filter { individuallyReviewedChatIDs.contains($0.chatID) }
    }

    private var unlabeledMessages: [ChatMessageRecord] {
        unknownSenderMessages.filter {
            !individuallyReviewedChatIDs.contains($0.chatID)
                && ParticipantLabelNormalizer.key($0.senderName) == nil
        }
    }

    private var showsSectionHeaders: Bool {
        !provisionalChats.isEmpty
            && (!visibleParticipantReviewGroups.isEmpty
                || !individualMessages.isEmpty
                || !unlabeledMessages.isEmpty)
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
                                        mergeLabel: mergeCandidateLabel,
                                        onConfirm: confirm,
                                        onMerge: merge
                                    )
                                }
                            }
                        }

                        if !visibleParticipantReviewGroups.isEmpty {
                            if showsSectionHeaders {
                                ImportReviewSectionHeader(title: "Sender identities")
                                    .padding(.top, 4)
                            }

                            VStack(spacing: 10) {
                                ForEach(visibleParticipantReviewGroups) { reviewGroup in
                                    ParticipantIdentityReviewCard(
                                        reviewGroup: reviewGroup,
                                        onSelect: resolveIdentity,
                                        onReviewIndividually: {
                                            individuallyReviewedChatIDs.insert(reviewGroup.chatID)
                                        }
                                    )
                                }
                            }
                        }

                        if !individualMessages.isEmpty {
                            ImportReviewSectionHeader(title: "Review messages individually")
                                .padding(.top, 4)

                            VStack(spacing: 10) {
                                ForEach(individualMessages) { message in
                                    UnknownSenderReviewCard(
                                        message: message,
                                        chatName: ChatPresentation.title(
                                            for: allChats.first(where: { $0.id == message.chatID })
                                        ),
                                        onResolve: resolveSender
                                    )
                                }
                            }
                        }

                        if !unlabeledMessages.isEmpty {
                            ImportReviewSectionHeader(title: "Messages without sender labels")
                                .padding(.top, 4)

                            VStack(spacing: 10) {
                                ForEach(unlabeledMessages) { message in
                                    UnknownSenderReviewCard(
                                        message: message,
                                        chatName: ChatPresentation.title(
                                            for: allChats.first(where: { $0.id == message.chatID })
                                        ),
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
                Text(verbatim: errorMessage ?? String(localized: AppStrings.Common.tryAgain))
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

    private func mergeCandidateLabel(_ candidate: ChatRecord) -> String {
        guard
            let alias =
                allChatContexts
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

    private func resolveIdentity(
        reviewGroup: ParticipantReviewGroup,
        selectedGroup: UnknownSenderLabelGroup
    ) {
        do {
            try ChatRepository().resolveUnknownSenderLabels(
                chatID: reviewGroup.chatID,
                selfLabel: selectedGroup.displayLabel
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ParticipantReviewGroup: Identifiable {
    let chatID: String
    let chatName: String
    let groups: [UnknownSenderLabelGroup]

    var id: String { chatID }
}

private struct ImportReviewSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(FrameReplyColor.onSurfaceVariant)
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
                    .foregroundStyle(FrameReplyColor.onSurface)

                Spacer(minLength: 8)

                Text(chatName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Text(message.text)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
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

private struct ParticipantIdentityReviewCard: View {
    let reviewGroup: ParticipantReviewGroup
    let onSelect: (ParticipantReviewGroup, UnknownSenderLabelGroup) -> Void
    let onReviewIndividually: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Which name is you?")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)

                Spacer(minLength: 8)

                Text(reviewGroup.chatName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    .lineLimit(1)
            }

            Text("Choose once to label every message from these authors.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)

            VStack(spacing: 8) {
                ForEach(reviewGroup.groups) { group in
                    Button {
                        onSelect(reviewGroup, group)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.displayLabel)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(FrameReplyColor.onSurface)

                                ForEach(Array(group.sampleMessages.enumerated()), id: \.offset) {
                                    _, sample in
                                    Text(sample)
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 8) {
                                Text("\(group.messageIDs.count) messages")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                                Label(
                                    "This is me",
                                    systemImage: "person.crop.circle.badge.checkmark"
                                )
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .frame(minHeight: 32)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(FrameReplyColor.primary)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(FrameReplyColor.secondaryContainer.opacity(0.5))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(FrameReplyColor.primary.opacity(0.22), lineWidth: 1)
                                }
                                .shadow(
                                    color: FrameReplyColor.primaryContainer.opacity(0.14),
                                    radius: 8,
                                    y: 4
                                )
                        }
                    }
                    .buttonStyle(SoftPressButtonStyle())
                    .accessibilityLabel(
                        "Choose \(group.displayLabel) as me, \(group.messageIDs.count) messages"
                    )
                }
            }

            Button("Review messages individually", action: onReviewIndividually)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.primary)
        }
        .padding(14)
        .quietReviewPanel(accented: true)
    }
}

private struct ImportReviewCard: View {
    let chat: ChatRecord
    let mergeCandidates: [ChatRecord]
    let mergeLabel: (ChatRecord) -> String
    let onConfirm: (String, String) -> Void
    let onMerge: (String, String) -> Void

    @State private var name: String

    private var presentation: Chat { Chat(record: chat) }

    init(
        chat: ChatRecord,
        mergeCandidates: [ChatRecord],
        mergeLabel: @escaping (ChatRecord) -> String,
        onConfirm: @escaping (String, String) -> Void,
        onMerge: @escaping (String, String) -> Void
    ) {
        self.chat = chat
        self.mergeCandidates = mergeCandidates
        self.mergeLabel = mergeLabel
        self.onConfirm = onConfirm
        self.onMerge = onMerge
        _name = State(initialValue: chat.displayTitle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                AvatarMark(
                    initials: presentation.initials,
                    symbolName: presentation.avatarSymbol,
                    colors: [FrameReplyColor.peach, FrameReplyColor.primaryContainer],
                    size: 34
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Imported chat")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                    TextField("Chat name", text: $name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurface)
                        .submitLabel(.done)
                        .onSubmit { KeyboardDismissal.dismiss() }
                }
            }

            Text(verbatim: chat.displayPreview())
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button {
                    onConfirm(chat.id, name)
                } label: {
                    Text("Keep")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 36)
                        .background {
                            Capsule(style: .continuous)
                                .fill(FrameReplyColor.primary)
                        }
                }
                .buttonStyle(SoftPressButtonStyle())

                if !mergeCandidates.isEmpty {
                    Menu {
                        ForEach(mergeCandidates) { candidate in
                            Button(mergeLabel(candidate)) {
                                onMerge(chat.id, candidate.id)
                            }
                        }
                    } label: {
                        Text("Merge into...")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(FrameReplyColor.primary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 36)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(FrameReplyColor.secondaryContainer.opacity(0.46))
                            }
                    }
                    .buttonStyle(SoftPressButtonStyle())
                }
            }
        }
        .padding(14)
        .quietReviewPanel()
        .onChange(of: chat.title) { _, _ in
            name = chat.displayTitle()
        }
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
                .foregroundStyle(FrameReplyColor.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 36)
                .background {
                    Capsule(style: .continuous)
                        .fill(FrameReplyColor.secondaryContainer.opacity(0.46))
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
                        .fill(FrameReplyColor.surfaceContainerLow.opacity(0.42))
                }
                .overlay(alignment: .leading) {
                    if accented {
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
}
