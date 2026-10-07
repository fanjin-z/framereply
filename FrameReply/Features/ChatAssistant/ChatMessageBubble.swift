//
//  ChatMessageBubble.swift
//  FrameReply
//

import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isFromUser || message.isSenderUnknown {
                Spacer(minLength: 52)
            }

            VStack(alignment: contentAlignment, spacing: 6) {
                if message.isSenderUnknown {
                    Label("Sender unknown", systemImage: "questionmark.circle.fill")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(FrameReplyColor.primary)
                }

                if let participantName = message.groupParticipantName {
                    Text(participantName)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(FrameReplyColor.primary)
                        .lineLimit(1)
                }

                Text(message.text)
                    .font(.system(.subheadline, design: .rounded, weight: .regular))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !message.timeLabel.isEmpty {
                    Text(message.timeLabel)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(FrameReplyColor.outline)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: message.accessibilityDescription))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: 360, alignment: frameAlignment)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(bubbleColor)
                    .shadow(
                        color: FrameReplyColor.primaryContainer.opacity(0.08), radius: 14, x: 0,
                        y: 8)
            }

            if !message.isFromUser || message.isSenderUnknown {
                Spacer(minLength: 52)
            }
        }
    }

    private var contentAlignment: HorizontalAlignment {
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
            ? FrameReplyColor.primaryFixed.opacity(0.72) : FrameReplyColor.fieldSurface
    }
}
