//
//  ChatImportReviewSheet.swift
//  FrameReply
//

import SwiftData
import SwiftUI

enum ImportReviewReadiness {
    static func canKeep(name: String, hasNamedUnresolvedSenders: Bool) -> Bool {
        !hasNamedUnresolvedSenders && IdentityLabelPolicy.displayLabel(name) != nil
    }
}

struct ChatImportReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allChats: [ChatRecord]
    @Query private var allChatContexts: [ChatContextRecord]
    @Query private var unknownSenderMessages: [ChatMessageRecord]
    @Query(sort: \ChatMessageRecord.sortIndex) private var allMessageRecords: [ChatMessageRecord]
    @State private var errorMessage: String?
    @State private var individuallyReviewedChatIDs: Set<String> = []
    @State private var directConversionChatID: String?

    private let chatID: String?
    private let onMerged: ((String) -> Void)?
    private let repository: ChatRepository

    init(
        chatID: String? = nil,
        repository: ChatRepository,
        onMerged: ((String) -> Void)? = nil
    ) {
        self.chatID = chatID
        self.repository = repository
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

    private var kindReviewChats: [ChatRecord] {
        allChats.filter {
            $0.importReviewState?.hasKindReview == true
                && (chatID == nil || $0.id == chatID)
        }
    }

    private var previouslyUsedSelfAliasLabels: [String] {
        ProvisionalIdentityResolver.previouslyUsedSelfAliasLabels(
            in: allChatContexts
        )
    }

    private var provisionalIdentitiesByChatID: [String: ProvisionalIdentityInterpretation] {
        Dictionary(
            uniqueKeysWithValues: provisionalChats.compactMap { chat in
                ProvisionalIdentityResolver.resolve(
                    chat: chat,
                    messages: unknownSenderMessages.filter { $0.chatID == chat.id },
                    previouslyUsedSelfAliasLabels: previouslyUsedSelfAliasLabels
                ).map { (chat.id, $0) }
            }
        )
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
            let provisionalIdentity = provisionalIdentitiesByChatID[id]
            return ParticipantReviewGroup(
                chatID: id,
                chatName: ChatPresentation.title(
                    for: allChats.first(where: { $0.id == id }),
                    provisionalIdentity: provisionalIdentity
                ),
                groups: groups.sorted {
                    let firstRemembered = rememberedAliasKeys.contains($0.normalizedLabel)
                    let secondRemembered = rememberedAliasKeys.contains($1.normalizedLabel)
                    if firstRemembered != secondRemembered {
                        return firstRemembered
                    }
                    return $0.displayLabel.localizedStandardCompare($1.displayLabel)
                        == .orderedAscending
                },
                rememberedAliasKeys: rememberedAliasKeys,
                conversationKind: allChats.first(where: { $0.id == id })?.conversationKind
                    ?? .direct,
                provisionalIdentity: provisionalIdentity
            )
        }
    }

    private var rememberedAliasKeys: Set<String> {
        Set(
            previouslyUsedSelfAliasLabels.compactMap {
                IdentityLabelPolicy.normalizedKey($0)
            }
        )
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
                        if !kindReviewChats.isEmpty {
                            ImportReviewSectionHeader(title: "Conversation type")
                            ForEach(kindReviewChats) { chat in
                                ConversationKindReviewCard(
                                    chat: chat,
                                    onAccept: acceptKindReview,
                                    onReject: rejectKindReview
                                )
                            }
                        }

                        if !visibleParticipantReviewGroups.isEmpty {
                            if showsSectionHeaders {
                                ImportReviewSectionHeader(title: "Sender identities")
                            }

                            VStack(spacing: 10) {
                                ForEach(visibleParticipantReviewGroups) { reviewGroup in
                                    ParticipantIdentityReviewCard(
                                        reviewGroup: reviewGroup,
                                        onSelect: resolveIdentity,
                                        onNotShown: resolveIdentityAsGroup,
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
                                        chatName: presentationTitle(chatID: message.chatID),
                                        conversationKind: conversationKind(
                                            chatID: message.chatID
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
                                        chatName: presentationTitle(chatID: message.chatID),
                                        conversationKind: conversationKind(
                                            chatID: message.chatID
                                        ),
                                        onResolve: resolveSender
                                    )
                                }
                            }
                        }

                        if !provisionalChats.isEmpty {
                            if showsSectionHeaders {
                                ImportReviewSectionHeader(title: "Imported chats")
                                    .padding(.top, 4)
                            }

                            VStack(spacing: 10) {
                                ForEach(provisionalChats) { chat in
                                    let provisionalIdentity =
                                        provisionalIdentitiesByChatID[chat.id]
                                    ImportReviewCard(
                                        chat: chat,
                                        provisionalIdentity: provisionalIdentity,
                                        mergeCandidates: confirmedChats.filter {
                                            $0.id != chat.id
                                        }.sorted {
                                            let suggestedID = chat.importReviewState?
                                                .suggestedMatchChatID
                                            if $0.id == suggestedID { return true }
                                            if $1.id == suggestedID { return false }
                                            return $0.updatedAt > $1.updatedAt
                                        },
                                        mergeLabel: mergeCandidateLabel,
                                        canConfirm: !participantReviewGroups.contains {
                                            $0.chatID == chat.id
                                        },
                                        onConfirm: confirm,
                                        onMerge: merge
                                    )
                                }
                            }
                        }

                        if provisionalChats.isEmpty && unknownSenderMessages.isEmpty
                            && kindReviewChats.isEmpty
                        {
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
            .sheet(isPresented: directConversionBinding) {
                DirectCounterpartSelectionSheet(
                    candidateNames: detectedParticipantNames(
                        chatID: directConversionChatID
                    ),
                    onSelect: convertReviewedChatToDirect
                )
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

    private func presentationTitle(chatID: String) -> String {
        ChatPresentation.title(
            for: allChats.first(where: { $0.id == chatID }),
            provisionalIdentity: provisionalIdentitiesByChatID[chatID]
        )
    }

    private func conversationKind(chatID: String) -> ChatConversationKind {
        allChats.first(where: { $0.id == chatID })?.conversationKind ?? .unknown
    }

    private func confirm(chatID: String, name: String) {
        KeyboardDismissal.dismiss()
        do {
            try repository.confirmProvisionalChat(chatID: chatID, name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func merge(provisionalChatID: String, targetChatID: String) {
        KeyboardDismissal.dismiss()
        do {
            try repository.mergeProvisionalChat(provisionalChatID, into: targetChatID)
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
            try repository.resolveUnknownSender(
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
            try repository.resolveUnknownSenderLabels(
                chatID: reviewGroup.chatID,
                selfLabel: selectedGroup.displayLabel
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveIdentityAsGroup(_ reviewGroup: ParticipantReviewGroup) {
        do {
            try repository.resolveUnknownSenderLabelsAsGroup(chatID: reviewGroup.chatID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func acceptKindReview(_ chat: ChatRecord) {
        do {
            if chat.conversationKind == .group {
                try repository.confirmConversationKind(chatID: chat.id)
            } else {
                try repository.reclassifyConversation(chatID: chat.id, to: .group)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rejectKindReview(_ chat: ChatRecord) {
        if chat.conversationKind == .group {
            directConversionChatID = chat.id
        } else {
            do {
                try repository.confirmConversationKind(chatID: chat.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var directConversionBinding: Binding<Bool> {
        Binding(
            get: { directConversionChatID != nil },
            set: { if !$0 { directConversionChatID = nil } }
        )
    }

    private func detectedParticipantNames(chatID: String?) -> [String] {
        guard let chatID else { return [] }
        var seen = Set<String>()
        return allMessageRecords.compactMap { message in
            guard message.chatID == chatID,
                message.senderKind != "user",
                let name = ParticipantLabelNormalizer.displayLabel(message.senderName),
                let key = ParticipantLabelNormalizer.key(name),
                seen.insert(key).inserted
            else { return nil }
            return name
        }
    }

    private func convertReviewedChatToDirect(_ name: String) {
        guard let chatID = directConversionChatID else { return }
        do {
            try repository.reclassifyConversation(
                chatID: chatID,
                to: .direct,
                directDisplayName: name
            )
            directConversionChatID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ParticipantReviewGroup: Identifiable {
    let chatID: String
    let chatName: String
    let groups: [UnknownSenderLabelGroup]
    let rememberedAliasKeys: Set<String>
    let conversationKind: ChatConversationKind
    let provisionalIdentity: ProvisionalIdentityInterpretation?

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
    let conversationKind: ChatConversationKind
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

                if conversationKind != .group {
                    SenderChoiceChip("Other Participant") {
                        onResolve(message.id, .otherParticipant, message.senderName)
                    }
                }

                if conversationKind != .direct {
                    SenderChoiceChip(message.senderName ?? "Participant") {
                        onResolve(message.id, .groupParticipant, message.senderName)
                    }
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
    let onNotShown: (ParticipantReviewGroup) -> Void
    let onReviewIndividually: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let provisionalIdentity = reviewGroup.provisionalIdentity {
                Text("Are you \(provisionalIdentity.selfDisplayLabel)?")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Which name is yours?")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurface)

                    Spacer(minLength: 8)

                    Text("Chat: \(reviewGroup.chatName)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                        .lineLimit(1)
                }

                Text("Choose your name if it appears here.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }

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

                                if reviewGroup.rememberedAliasKeys.contains(
                                    group.normalizedLabel
                                ) {
                                    Text("Used as your name before")
                                        .font(
                                            .system(
                                                size: 11,
                                                weight: .semibold,
                                                design: .rounded
                                            )
                                        )
                                        .foregroundStyle(FrameReplyColor.primary)
                                }

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

                                identityActionLabel(
                                    actionTitle(for: group),
                                    systemImage: "person.crop.circle.badge.checkmark",
                                    foregroundColor: .white,
                                    backgroundColor: FrameReplyColor.primary
                                )
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

            if reviewGroup.conversationKind == .group
                || (reviewGroup.conversationKind == .direct && reviewGroup.groups.count >= 2)
            {
                HStack {
                    Spacer(minLength: 0)

                    Button {
                        onNotShown(reviewGroup)
                    } label: {
                        identityActionLabel(
                            "None of These",
                            systemImage: "person.crop.circle.badge.xmark",
                            foregroundColor: FrameReplyColor.secondary,
                            backgroundColor: FrameReplyColor.secondaryContainer
                        )
                    }
                    .buttonStyle(SoftPressButtonStyle())
                    .accessibilityLabel("None of these names is me")
                }
                .padding(.trailing, 14)
            }

            Button("Review messages individually", action: onReviewIndividually)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.primary)
        }
        .padding(14)
        .quietReviewPanel(accented: true)
    }

    private func actionTitle(for group: UnknownSenderLabelGroup) -> LocalizedStringKey {
        guard let provisionalIdentity = reviewGroup.provisionalIdentity else {
            return "This Is Me"
        }
        return IdentityLabelPolicy.normalizedKey(provisionalIdentity.selfDisplayLabel)
            == group.normalizedLabel
            ? "Yes"
            : "No, This Is Me"
    }

    private func identityActionLabel(
        _ title: LocalizedStringKey,
        systemImage: String,
        foregroundColor: Color,
        backgroundColor: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(foregroundColor)
            .frame(width: 132, height: 32)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            }
            .contentShape(Capsule(style: .continuous))
    }
}

private struct ConversationKindReviewCard: View {
    let chat: ChatRecord
    let onAccept: (ChatRecord) -> Void
    let onReject: (ChatRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "person.2.fill")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)

            Text(message)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)

            HStack(spacing: 10) {
                Button(primaryTitle) { onAccept(chat) }
                    .buttonStyle(.borderedProminent)
                Button(secondaryTitle) { onReject(chat) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .quietReviewPanel(accented: true)
    }

    private var wasApplied: Bool { chat.conversationKind == .group }
    private var title: String {
        wasApplied ? "Converted to Group" : "This may be a group chat"
    }
    private var message: String {
        wasApplied
            ? "FrameReply found structural evidence of multiple participants in \(chat.displayTitle())."
            : "The importer suspected multiple participants but did not find enough structural evidence to change this Direct chat automatically."
    }
    private var primaryTitle: String { wasApplied ? "Keep Group" : "Convert" }
    private var secondaryTitle: String { wasApplied ? "Change to Direct" : "Keep Direct" }
}

private struct ImportReviewCard: View {
    let chat: ChatRecord
    let provisionalIdentity: ProvisionalIdentityInterpretation?
    let mergeCandidates: [ChatRecord]
    let mergeLabel: (ChatRecord) -> String
    let canConfirm: Bool
    let onConfirm: (String, String) -> Void
    let onMerge: (String, String) -> Void

    @State private var name: String

    private var presentation: Chat {
        Chat(record: chat, provisionalIdentity: provisionalIdentity)
    }

    init(
        chat: ChatRecord,
        provisionalIdentity: ProvisionalIdentityInterpretation?,
        mergeCandidates: [ChatRecord],
        mergeLabel: @escaping (ChatRecord) -> String,
        canConfirm: Bool,
        onConfirm: @escaping (String, String) -> Void,
        onMerge: @escaping (String, String) -> Void
    ) {
        self.chat = chat
        self.provisionalIdentity = provisionalIdentity
        self.mergeCandidates = mergeCandidates
        self.mergeLabel = mergeLabel
        self.canConfirm = canConfirm
        self.onConfirm = onConfirm
        self.onMerge = onMerge
        _name = State(
            initialValue:
                chat.title
                ?? provisionalIdentity?.displayTitle
                ?? (chat.conversationKind == .group ? chat.displayTitle() : "")
        )
    }

    private var canKeep: Bool {
        ImportReviewReadiness.canKeep(
            name: name,
            hasNamedUnresolvedSenders: !canConfirm
        )
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
                if let suggestedCandidate {
                    Button {
                        onMerge(chat.id, suggestedCandidate.id)
                    } label: {
                        Text("Merge into \(mergeLabel(suggestedCandidate))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 36)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(FrameReplyColor.primary)
                            }
                    }
                    .buttonStyle(SoftPressButtonStyle())

                    keepButton(prominent: false)
                } else {
                    keepButton(prominent: true)
                    if !mergeCandidates.isEmpty {
                        mergeMenu(candidates: mergeCandidates, title: "Merge into...")
                    }
                }
            }

            if suggestedCandidate != nil, !otherMergeCandidates.isEmpty {
                mergeMenu(candidates: otherMergeCandidates, title: "Other destinations...")
            }
        }
        .padding(14)
        .quietReviewPanel()
        .onChange(of: chat.title) { _, _ in
            name =
                chat.title
                ?? provisionalIdentity?.displayTitle
                ?? (chat.conversationKind == .group ? chat.displayTitle() : "")
        }
    }

    private func candidateLabel(_ candidate: ChatRecord) -> String {
        var label = mergeLabel(candidate)
        if candidate.id == chat.importReviewState?.suggestedMatchChatID {
            label += " · Suggested"
        }
        if !chat.conversationKind.isCompatible(with: candidate.conversationKind) {
            label += " · Result: Group"
        }
        return label
    }

    private var suggestedCandidate: ChatRecord? {
        guard let suggestedID = chat.importReviewState?.suggestedMatchChatID else {
            return nil
        }
        return mergeCandidates.first { $0.id == suggestedID }
    }

    private var otherMergeCandidates: [ChatRecord] {
        guard let suggestedCandidate else { return mergeCandidates }
        return mergeCandidates.filter { $0.id != suggestedCandidate.id }
    }

    private func keepButton(prominent: Bool) -> some View {
        Button {
            onConfirm(chat.id, name)
        } label: {
            Text(prominent ? "Keep" : "Keep Separate")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(prominent ? Color.white : FrameReplyColor.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 36)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            prominent
                                ? FrameReplyColor.primary
                                : FrameReplyColor.secondaryContainer.opacity(0.46)
                        )
                }
        }
        .buttonStyle(SoftPressButtonStyle())
        .disabled(!canKeep)
        .opacity(canKeep ? 1 : 0.48)
    }

    private func mergeMenu(candidates: [ChatRecord], title: String) -> some View {
        Menu {
            ForEach(candidates) { candidate in
                Button(candidateLabel(candidate)) {
                    onMerge(chat.id, candidate.id)
                }
            }
        } label: {
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
