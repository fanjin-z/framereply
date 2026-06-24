//
//  ChatMessageBubble.swift
//  zeptly
//

import SwiftUI

struct ChatMessageBubble: View {
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
