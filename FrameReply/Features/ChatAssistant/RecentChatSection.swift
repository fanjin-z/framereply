//
//  RecentChatSection.swift
//  FrameReply
//

import SwiftUI

struct RecentChatSection: View {
    let messages: [ChatMessage]
    let onHistoryTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(symbolName: "bubble.left.and.text.bubble.right", title: "Recent Chat") {
                Button(action: onHistoryTap) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(FrameReplyColor.primary)
                    .padding(.leading, 10)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens full chat history")
                .accessibilityIdentifier("recent-chat-view-all")
            }

            Button(action: onHistoryTap) {
                VStack(spacing: 8) {
                    if messages.isEmpty {
                        Text(AppStrings.Chat.previewFallback)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(FrameReplyColor.outline)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else {
                        ForEach(messages) { message in
                            CompactChatMessageBubble(message: message)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.48))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        }
                }
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityHint("Opens full chat history")
            .accessibilityIdentifier("recent-chat-preview")
        }
    }
}

private struct CompactChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isFromUser || message.isSenderUnknown {
                Spacer(minLength: 36)
            }

            VStack(alignment: contentAlignment, spacing: 3) {
                if message.isSenderUnknown {
                    Label("Sender unknown", systemImage: "questionmark.circle.fill")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(FrameReplyColor.primary)
                }

                Text(message.text)
                    .font(.system(.subheadline, design: .rounded, weight: .regular))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(textAlignment)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: 360, alignment: frameAlignment)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(bubbleColor)
            }

            if !message.isFromUser || message.isSenderUnknown {
                Spacer(minLength: 36)
            }
        }
    }

    private var contentAlignment: HorizontalAlignment {
        message.isSenderUnknown ? .center : (message.isFromUser ? .trailing : .leading)
    }

    private var textAlignment: TextAlignment {
        message.isSenderUnknown ? .center : (message.isFromUser ? .trailing : .leading)
    }

    private var frameAlignment: Alignment {
        message.isSenderUnknown ? .center : (message.isFromUser ? .trailing : .leading)
    }

    private var bubbleColor: Color {
        if message.isSenderUnknown {
            return FrameReplyColor.surfaceVariant.opacity(0.9)
        }
        return message.isFromUser
            ? FrameReplyColor.primaryFixed.opacity(0.72) : Color.white.opacity(0.82)
    }
}

private struct RecentChatSection_Previews: PreviewProvider {
    static let shortMessages = [
        ChatMessage(
            sender: .user, text: "Dinner isn't necessary—I just ate.", timeLabel: "2:00 PM"),
        ChatMessage(
            sender: .otherParticipant, text: "Then I'll buy some bread.", timeLabel: "2:01 PM"),
        ChatMessage(
            sender: .otherParticipant, text: "If you want food, cook noodles.",
            timeLabel: "2:01 PM")
    ]

    static let longMessages = [
        ChatMessage(
            sender: .groupParticipant("Alex"),
            text: "This deliberately long message demonstrates the two-line compact preview "
                + "and truncation behavior.",
            timeLabel: "Yesterday"
        ),
        ChatMessage(sender: .unknown, text: "Unknown sender preview", timeLabel: "Yesterday")
    ]

    static var previews: some View {
        Group {
            RecentChatSection(messages: shortMessages, onHistoryTap: {})
                .previewDisplayName("Short messages")

            RecentChatSection(messages: longMessages, onHistoryTap: {})
                .previewDisplayName("Long and unknown")

            RecentChatSection(messages: [], onHistoryTap: {})
                .previewDisplayName("Empty")

            RecentChatSection(messages: shortMessages, onHistoryTap: {})
                .environment(\.dynamicTypeSize, .accessibility5)
                .previewDisplayName("Accessibility XXXL")
        }
        .padding(24)
        .frame(width: 390)
        .background(EtherealBackground())
        .previewLayout(.sizeThatFits)
    }
}
