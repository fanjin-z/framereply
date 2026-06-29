//
//  ChatMessageBubble.swift
//  zeptly
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
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(RezplyColor.primary)
                }

                Text(message.text)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !message.timeLabel.isEmpty {
                    Text(message.timeLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(RezplyColor.outline)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
                .frame(maxWidth: 360, alignment: frameAlignment)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(bubbleColor)
                    .shadow(color: RezplyColor.primaryContainer.opacity(0.08), radius: 14, x: 0, y: 8)
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
            return RezplyColor.surfaceVariant.opacity(0.9)
        }
        return message.isFromUser ? RezplyColor.primaryFixed.opacity(0.72) : Color.white.opacity(0.82)
    }
}
