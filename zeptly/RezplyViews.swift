//
//  RezplyViews.swift
//  zeptly
//

import SwiftUI

private enum RezplyRoute: Hashable {
    case contactContext(String)
    case chatIntelligence(String)
}

struct RezplyShellView: View {
    @State private var selectedTab: AppTab = .inbox
    @State private var providers = RezplySampleData.providers
    @State private var navigationPath: [RezplyRoute] = []
    @State private var contactContexts = RezplySampleData.initialContactContexts

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                EtherealBackground()

                VStack(spacing: 0) {
                    TopAppBar(selectedTab: selectedTab)

                    Group {
                        switch selectedTab {
                        case .inbox:
                            InboxView(
                                onChatTap: { chat in
                                    navigationPath.append(.chatIntelligence(chat.id))
                                },
                                onAvatarTap: { chat in
                                    navigationPath.append(.contactContext(chat.id))
                                }
                            )
                        case .personas:
                            PersonasView()
                        case .settings:
                            SettingsView(providers: $providers)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                FloatingBottomNavigation(selectedTab: $selectedTab)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
            }
            .navigationDestination(for: RezplyRoute.self) { route in
                switch route {
                case let .contactContext(chatID):
                    if let chat = RezplySampleData.chat(withID: chatID) {
                        ContactContextView(
                            chat: chat,
                            context: contactContextBinding(for: chat)
                        )
                    }
                case let .chatIntelligence(chatID):
                    if let chat = RezplySampleData.chat(withID: chatID) {
                        ChatIntelligenceView(
                            chat: chat,
                            intelligence: RezplySampleData.chatIntelligence(withID: chatID),
                            onContactTap: {
                                navigationPath.append(.contactContext(chatID))
                            }
                        )
                    }
                }
            }
        }
        .tint(RezplyColor.primary)
    }

    private func contactContextBinding(for chat: Chat) -> Binding<ContactContext> {
        Binding(
            get: {
                contactContexts[chat.id] ?? chat.contactContext ?? ContactContext.empty
            },
            set: { newValue in
                contactContexts[chat.id] = newValue
            }
        )
    }
}

private struct TopAppBar: View {
    let selectedTab: AppTab

    var body: some View {
        HStack {
            Button {
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(RezplyColor.primary)

            Spacer()

            Text("Rezply")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(RezplyColor.primary)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)

            Spacer()

            ProfileButton(selectedTab: selectedTab)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(RezplyColor.surface.opacity(0.42))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.36))
                        .frame(height: 1)
                }
        }
    }
}

private struct ProfileButton: View {
    let selectedTab: AppTab

    var body: some View {
        Button {
        } label: {
            if selectedTab == .settings {
                Circle()
                    .fill(RezplyColor.primaryContainer)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(RezplyColor.primary)
                    }
            } else {
                AvatarMark(
                    initials: "R",
                    symbolName: nil,
                    colors: selectedTab == .personas
                        ? [RezplyColor.peach, RezplyColor.secondary]
                        : [RezplyColor.primaryContainer, RezplyColor.peach],
                    size: 36
                )
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
    }
}

private struct InboxView: View {
    let onChatTap: (Chat) -> Void
    let onAvatarTap: (Chat) -> Void
    @State private var searchText = ""

    private var chats: [Chat] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RezplySampleData.chats
        }

        return RezplySampleData.chats.filter { chat in
            chat.name.localizedCaseInsensitiveContains(searchText)
                || chat.preview.localizedCaseInsensitiveContains(searchText)
                || chat.chipTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SearchField(text: $searchText)
                    .padding(.top, 14)

                VStack(spacing: 16) {
                    ForEach(chats) { chat in
                        ChatRow(
                            chat: chat,
                            onChatTap: {
                                onChatTap(chat)
                            },
                            onAvatarTap: {
                                onAvatarTap(chat)
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
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(RezplyColor.outlineVariant)

            TextField("Search chats...", text: $text)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.82))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(RezplyColor.outline.opacity(0.9), lineWidth: 1.4)
                }
                .shadow(color: RezplyColor.primaryContainer.opacity(0.08), radius: 20, x: 0, y: 10)
        }
    }
}

private struct ChatRow: View {
    let chat: Chat
    let onChatTap: () -> Void
    let onAvatarTap: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            avatar

            Button {
                onChatTap()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(chat.name)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer(minLength: 12)

                        Text(chat.timeLabel)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(chat.isUnread ? RezplyColor.primary : RezplyColor.outline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    PillChip(
                        title: chat.chipTitle,
                        symbolName: chat.chipSymbol,
                        tint: chat.isUnread ? RezplyColor.primaryContainer : RezplyColor.secondary
                    )
                    .fixedSize(horizontal: true, vertical: true)

                    Text(chat.preview)
                        .font(.system(size: 15, weight: chat.isUnread ? .medium : .regular, design: .rounded))
                        .foregroundStyle(chat.isUnread ? RezplyColor.onSurfaceVariant : RezplyColor.outline)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Chat Intelligence for \(chat.name)")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(minHeight: 86)
        .glassPanel(cornerRadius: 22)
        .overlay(alignment: .leading) {
            if chat.isUnread {
                UnevenRoundedRectangle(
                    topLeadingRadius: 22,
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(RezplyColor.primary)
                .frame(width: 5)
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        let mark = AvatarMark(
            initials: chat.initials,
            symbolName: chat.avatarSymbol,
            colors: chat.gradient,
            size: 50,
            showsOnline: chat.isOnline
        )

        Button {
            onAvatarTap()
        } label: {
            mark
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel("Open contact context for \(chat.name)")
    }
}

private struct EmptySearchState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 30, weight: .light))
            Text("No chats found")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(RezplyColor.outline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .glassPanel(cornerRadius: 26)
    }
}

private struct ChatIntelligenceView: View {
    let chat: Chat
    let intelligence: ChatIntelligence
    let onContactTap: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isHistoryPresented = false
    @State private var isContextPresented = false
    @State private var isScreenshotAttached = false
    @State private var contextNote = ""
    @State private var copiedReplyID: UUID?

    private var latestMessages: [ChatMessage] {
        Array(intelligence.messages.suffix(3))
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
                        onContactTap: onContactTap
                    )

                    ChatContextChipPanel(chips: intelligence.contextChips)

                    RecentChatSection(
                        messages: latestMessages,
                        onSearchTap: {
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
                        replies: intelligence.suggestedReplies,
                        copiedReplyID: copiedReplyID,
                        onCopy: copyReply
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
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isHistoryPresented) {
            ChatHistorySheet(chat: chat, messages: intelligence.messages)
        }
        .sheet(isPresented: $isContextPresented) {
            AddChatContextSheet(note: $contextNote)
        }
    }

    private func copyReply(_ reply: SuggestedReply) {
        ClipboardWriter.copy(reply.text)

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            copiedReplyID = reply.id
        }
    }
}

private struct ChatIntelligenceTopBar: View {
    let chat: Chat
    let onBackTap: () -> Void
    let onContactTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onBackTap()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(RezplyColor.primary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Back to inbox")

            Button {
                onContactTap()
            } label: {
                HStack(spacing: 12) {
                    AvatarMark(
                        initials: chat.initials,
                        symbolName: chat.avatarSymbol,
                        colors: chat.gradient,
                        size: 42,
                        showsOnline: chat.isOnline
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.name)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(chat.isOnline ? "Online" : "Chat Intel")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open contact context for \(chat.name)")

            Spacer(minLength: 8)

            Button {
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(RezplyColor.primary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, 2)
    }
}

private struct ChatContextChipPanel: View {
    let chips: [String]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 126), spacing: 10, alignment: .leading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(chips, id: \.self) { chip in
                PillChip(title: chip, symbolName: symbol(for: chip), tint: RezplyColor.primary)
                    .fixedSize(horizontal: true, vertical: true)
            }

            Button {
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RezplyColor.onSurface)
                    .frame(width: 48, height: 48)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.72))
                            .shadow(color: RezplyColor.primaryContainer.opacity(0.12), radius: 16, x: 0, y: 8)
                    }
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Edit chat intelligence")
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .glassPanel(cornerRadius: 30)
    }

    private func symbol(for chip: String) -> String {
        if chip.localizedCaseInsensitiveContains("schedule") {
            return "flag"
        }
        if chip.localizedCaseInsensitiveContains("professional") {
            return "person.crop.circle.badge.checkmark"
        }
        if chip.localizedCaseInsensitiveContains("creative") {
            return "sparkles"
        }
        return "lightbulb"
    }
}

private struct RecentChatSection: View {
    let messages: [ChatMessage]
    let onSearchTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(symbolName: "bubble.left.and.text.bubble.right", title: "Recent Chat") {
                Button {
                    onSearchTap()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(RezplyColor.primary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(SoftPressButtonStyle())
                .accessibilityLabel("Search all chat history")
            }

            VStack(spacing: 12) {
                ForEach(messages) { message in
                    ChatMessageBubble(message: message)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.48))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    }
            }
        }
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer(minLength: 52)
            }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 6) {
                Text(message.text)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message.timeLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(RezplyColor.outline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: 360, alignment: message.isFromUser ? .trailing : .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(message.isFromUser ? RezplyColor.primaryFixed.opacity(0.72) : Color.white.opacity(0.82))
                    .shadow(color: RezplyColor.primaryContainer.opacity(0.08), radius: 14, x: 0, y: 8)
            }

            if !message.isFromUser {
                Spacer(minLength: 52)
            }
        }
    }
}

private struct ChatCaptureControls: View {
    let isScreenshotAttached: Bool
    let hasContextNote: Bool
    let onAttachTap: () -> Void
    let onContextTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onAttachTap()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: isScreenshotAttached ? "checkmark.circle" : "camera.badge.ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                    Text(isScreenshotAttached ? "Screenshot Added" : "Attach Screenshot")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(RezplyColor.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    Capsule(style: .continuous)
                        .fill(RezplyColor.secondaryContainer.opacity(0.42))
                }
            }
            .buttonStyle(SoftPressButtonStyle())

            Button {
                onContextTap()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: hasContextNote ? "checkmark.bubble" : "text.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text(hasContextNote ? "Context Added" : "Add Context")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    Capsule(style: .continuous)
                        .fill(RezplyColor.primary)
                        .shadow(color: RezplyColor.primaryContainer.opacity(0.28), radius: 18, x: 0, y: 10)
                }
            }
            .buttonStyle(SoftPressButtonStyle())
        }
    }
}

private struct SuggestedRepliesSection: View {
    let replies: [SuggestedReply]
    let copiedReplyID: UUID?
    let onCopy: (SuggestedReply) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "rectangle.on.rectangle.angled", title: "Suggested Replies")

            VStack(spacing: 14) {
                ForEach(replies) { reply in
                    SuggestedReplyCard(
                        reply: reply,
                        isCopied: copiedReplyID == reply.id,
                        onCopy: {
                            onCopy(reply)
                        }
                    )
                }
            }
        }
    }
}

private struct SuggestedReplyCard: View {
    let reply: SuggestedReply
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(reply.text)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onCopy()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background {
                    Capsule(style: .continuous)
                        .fill(RezplyColor.primary)
                }
            }
            .buttonStyle(SoftPressButtonStyle())
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(22)
        .glassPanel(cornerRadius: 24)
    }
}

private struct SuggestedActionCard: View {
    let action: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "wand.and.stars", title: "Suggested Next Step")

            Text(action)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .glassPanel(cornerRadius: 24)
    }
}

private struct ChatReasoningCard: View {
    let reasoning: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Strategy Reasoning")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(RezplyColor.outline)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(RezplyColor.primary)
                    .frame(width: 24)

                Text(reasoning)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurfaceVariant)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(RezplyColor.secondaryContainer.opacity(0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.34), lineWidth: 1)
                    }
            }
        }
    }
}

private struct ChatHistorySheet: View {
    let chat: Chat
    let messages: [ChatMessage]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredMessages: [ChatMessage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return messages
        }

        return messages.filter { message in
            message.text.localizedCaseInsensitiveContains(query)
                || message.timeLabel.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            EtherealBackground()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Chat History")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)

                        Text(chat.name)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(RezplyColor.primary)
                            .frame(width: 38, height: 38)
                            .background {
                                Circle()
                                    .fill(Color.white.opacity(0.72))
                            }
                    }
                    .buttonStyle(SoftPressButtonStyle())
                    .accessibilityLabel("Close chat history")
                }

                SearchField(text: $searchText)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(filteredMessages) { message in
                            ChatMessageBubble(message: message)
                        }

                        if filteredMessages.isEmpty {
                            EmptySearchState()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct AddChatContextSheet: View {
    @Binding var note: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EtherealBackground()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Add Context")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)

                        Text("Offline notes for this reply")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(RezplyColor.primary)
                            }
                    }
                    .buttonStyle(SoftPressButtonStyle())
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $note)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 180)

                    if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add what happened offline, what you want to accomplish, or anything the screenshot might miss...")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(RezplyColor.outline)
                            .lineSpacing(4)
                            .padding(20)
                            .allowsHitTesting(false)
                    }
                }
                .glassPanel(cornerRadius: 24)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private struct ContactContextView: View {
    let chat: Chat
    @Binding var context: ContactContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(RezplyColor.primary)
                            .frame(width: 46, height: 46)
                            .background {
                                Circle()
                                    .fill(Color.white.opacity(0.68))
                                    .shadow(color: RezplyColor.primaryContainer.opacity(0.12), radius: 18, x: 0, y: 10)
                            }
                    }
                    .buttonStyle(SoftPressButtonStyle())
                    .accessibilityLabel("Back to inbox")

                    ContactProfileCard(chat: chat, subtitle: context.relationshipSubtitle)

                    RelationshipContextCard(notes: $context.relationshipNotes)

                    KeyFactsCard(facts: $context.keyFacts)

                    ContactContextInfoGrid(
                        currentInteractionGoal: $context.currentInteractionGoal,
                        preferredPersona: $context.preferredPersona
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ContactProfileCard: View {
    let chat: Chat
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            AvatarMark(
                initials: chat.initials,
                symbolName: chat.avatarSymbol,
                colors: chat.gradient,
                size: 96,
                showsOnline: chat.isOnline
            )
            .padding(.top, 8)

            VStack(spacing: 7) {
                Text(chat.name)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(subtitle)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .glassPanel(cornerRadius: 34)
    }
}

private struct RelationshipContextCard: View {
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(symbolName: "hand.wave", title: "Relationship Context") {
                Text("Auto-saved")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RezplyColor.outline)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.46))
                    }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 116)

                if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add notes about your history, how you met, or overarching dynamics...")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface.opacity(0.86))
                        .lineSpacing(4)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(RezplyColor.secondaryContainer.opacity(0.28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    }
            }
        }
        .padding(24)
        .glassPanel(cornerRadius: 30)
    }
}

private struct KeyFactsCard: View {
    @Binding var facts: [String]
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(symbolName: "key", title: "Key Facts") {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isEditing.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 12, weight: .bold))
                        Text(isEditing ? "Done" : "Edit")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(RezplyColor.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.primaryContainer.opacity(0.16))
                            .shadow(color: RezplyColor.primaryContainer.opacity(0.18), radius: 12, x: 0, y: 6)
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
            }

            VStack(alignment: .leading, spacing: 11) {
                ForEach(facts.indices, id: \.self) { index in
                    if isEditing {
                        EditableFactRow(
                            fact: Binding(
                                get: { facts[index] },
                                set: { facts[index] = $0 }
                            ),
                            onDelete: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    facts = facts.enumerated()
                                        .filter { $0.offset != index }
                                        .map(\.element)
                                }
                            }
                        )
                    } else {
                        FactChip(title: facts[index])
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        facts.append("New fact")
                        isEditing = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Add Fact")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(RezplyColor.primary)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background {
                        Capsule(style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(RezplyColor.outline.opacity(0.72))
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .padding(.top, 2)
            }
        }
        .padding(24)
        .glassPanel(cornerRadius: 30)
    }
}

private struct ContactContextInfoGrid: View {
    @Binding var currentInteractionGoal: String
    @Binding var preferredPersona: String

    private let personaOptions = [
        "Warm & Collaborative",
        "Professional",
        "Creative",
        "Minimalist"
    ]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 240), spacing: 16)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(symbolName: "target", title: "Current Interaction Goal")

                ContactContextField(text: $currentInteractionGoal, placeholder: "e.g., Close Q3 proposal...")
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 28)

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(symbolName: "theatermasks", title: "Preferred Persona")

                Menu {
                    ForEach(personaOptions, id: \.self) { option in
                        Button(option) {
                            preferredPersona = option
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(preferredPersona)
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.secondaryContainer.opacity(0.28))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.36), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 28)
        }
    }
}

private struct ContactContextField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.outline)
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
            }

            TextField("", text: $text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 16)
        }
        .frame(height: 48)
        .background {
            Capsule(style: .continuous)
                .fill(RezplyColor.secondaryContainer.opacity(0.28))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.36), lineWidth: 1)
                }
        }
    }
}

private struct EditableFactRow: View {
    @Binding var fact: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Fact", text: $fact)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)
                .textInputAutocapitalization(.sentences)

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(RezplyColor.outline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete fact")
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background {
            Capsule(style: .continuous)
                .fill(RezplyColor.secondaryContainer.opacity(0.32))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                }
        }
    }
}

private struct FactChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(RezplyColor.onSurfaceVariant)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background {
                Capsule(style: .continuous)
                    .fill(RezplyColor.secondaryContainer.opacity(0.42))
                    .shadow(color: RezplyColor.primaryContainer.opacity(0.1), radius: 10, x: 0, y: 5)
            }
    }
}

private struct SectionHeader<Trailing: View>: View {
    let symbolName: String
    let title: String
    @ViewBuilder let trailing: Trailing

    init(symbolName: String, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.symbolName = symbolName
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RezplyColor.primary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 12)

            trailing
        }
    }
}

private extension SectionHeader where Trailing == EmptyView {
    init(symbolName: String, title: String) {
        self.init(symbolName: symbolName, title: title) {
            EmptyView()
        }
    }
}

private struct PersonasView: View {
    @State private var didTapCreate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 12) {
                    ForEach(RezplySampleData.personas) { persona in
                        PersonaCard(persona: persona)
                    }
                }
                .padding(.top, 14)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        didTapCreate.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .medium))
                        Text(didTapCreate ? "Ready to Create" : "Create New Persona")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.primary)
                            .shadow(color: RezplyColor.primaryContainer.opacity(0.34), radius: 22, x: 0, y: 12)
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 94)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct PersonaCard: View {
    let persona: Persona

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Circle()
                    .fill(persona.accent.opacity(0.12))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: persona.symbolName)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(persona.accent)
                    }

                Spacer()

                Button {
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(RezplyColor.outline)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(persona.title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(persona.summary)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .lineSpacing(2)
                    .foregroundStyle(RezplyColor.onSurfaceVariant.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                ForEach(persona.tags, id: \.self) { tag in
                    PillChip(title: tag, tint: RezplyColor.secondary)
                }
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 24)
    }
}

private struct SettingsView: View {
    @Binding var providers: [ProviderConnection]
    @State private var selectedPlatform = "Select provider..."
    @State private var selectedEnvironment = "Production"
    @State private var apiKey = ""
    @State private var didConnect = false

    private let platforms = ["Select provider...", "Google Gemini", "Cohere", "Mistral AI", "Custom Endpoint"]
    private let environments = ["Production", "Development", "Staging"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image(systemName: "network")
                            .font(.system(size: 20, weight: .medium))
                        Text("Active Connections")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(RezplyColor.primary)
                    .padding(.top, 16)

                    VStack(spacing: 18) {
                        ForEach($providers) { $provider in
                            ProviderCard(provider: $provider)
                        }
                    }
                }

                AddProviderCard(
                    selectedPlatform: $selectedPlatform,
                    selectedEnvironment: $selectedEnvironment,
                    apiKey: $apiKey,
                    didConnect: $didConnect,
                    platforms: platforms,
                    environments: environments
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 94)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ProviderCard: View {
    @Binding var provider: ProviderConnection

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 42, height: 42)
                    .shadow(color: RezplyColor.primaryContainer.opacity(0.18), radius: 12, x: 0, y: 8)
                    .overlay {
                        Image(systemName: provider.symbolName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(RezplyColor.primary)
                    }

                VStack(alignment: .leading, spacing: 7) {
                    Text(provider.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)

                    PillChip(title: provider.model, tint: RezplyColor.primary)
                }

                Spacer()

                Toggle("", isOn: $provider.isEnabled)
                    .labelsHidden()
                    .tint(RezplyColor.primary)
            }

            VStack(spacing: 14) {
                SettingStatusRow(title: "Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(provider.isEnabled ? RezplyColor.connected : RezplyColor.outlineVariant)
                            .frame(width: 8, height: 8)
                        Text(provider.isEnabled ? "Connected" : "Paused")
                    }
                }

                SettingStatusRow(title: "Last synced") {
                    Text(provider.lastSynced)
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.white.opacity(0.42))
        }
    }
}

private struct SettingStatusRow<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)

            Spacer()

            value
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.primary)
        }
    }
}

private struct AddProviderCard: View {
    @Binding var selectedPlatform: String
    @Binding var selectedEnvironment: String
    @Binding var apiKey: String
    @Binding var didConnect: Bool

    let platforms: [String]
    let environments: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add New Provider")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)

                Text("Connect a new language model API securely to your workspace.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .lineSpacing(2)
                    .foregroundStyle(RezplyColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                PickerField(title: "Provider Platform", selection: $selectedPlatform, options: platforms)
                PickerField(title: "Environment", selection: $selectedEnvironment, options: environments)

                VStack(alignment: .leading, spacing: 9) {
                    Text("API Key")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)

                    HStack {
                        SecureField("sk-...", text: $apiKey)
                            .font(.system(size: 16, weight: .regular, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Image(systemName: "eye")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .background {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.white.opacity(0.56))
                    }

                    Text("Keys are encrypted end-to-end and never stored in plain text.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(0.6)
                        .lineSpacing(3)
                        .foregroundStyle(RezplyColor.outline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        didConnect = true
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: didConnect ? "checkmark" : "link")
                        Text(didConnect ? "Provider Queued" : "Connect Provider")
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 48)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.primary)
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 8)
            }
        }
        .padding(22)
        .glassPanel(cornerRadius: 26)
    }
}

private struct PickerField: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        selection = option
                    }
                }
            } label: {
                HStack {
                    Text(selection)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RezplyColor.onSurfaceVariant)
                }
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.white.opacity(0.56))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct FloatingBottomNavigation: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: selectedTab == tab ? "\(tab.symbolName).fill" : tab.symbolName)
                            .font(.system(size: 23, weight: .medium))
                            .frame(height: 24)

                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(0.4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(selectedTab == tab ? RezplyColor.primary : Color.black.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .frame(height: 50)
                    .background {
                        if selectedTab == tab {
                            Capsule(style: .continuous)
                                .fill(RezplyColor.primaryContainer.opacity(0.8))
                                .shadow(color: RezplyColor.primaryContainer.opacity(0.4), radius: 15, x: 0, y: 8)
                        }
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 560)
        .frame(height: 66)
        .glassPanel(cornerRadius: 34)
    }
}

private struct SoftPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct RezplyShellView_Previews: PreviewProvider {
    static var previews: some View {
        RezplyShellView()
            .previewDisplayName("Rezply Shell")
    }
}
