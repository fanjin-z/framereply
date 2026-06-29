//
//  RecentChatSection.swift
//  zeptly
//

import SwiftUI

struct RecentChatSection: View {
    let messages: [ChatMessage]
    let onHistoryTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(symbolName: "bubble.left.and.text.bubble.right", title: "Recent Chat") {
                Button {
                    onHistoryTap()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(RezplyColor.primary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(SoftPressButtonStyle())
                .accessibilityLabel("Search all chat history")
            }

            Button {
                onHistoryTap()
            } label: {
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
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Open chat history")
        }
    }
}
