//
//  ChatAssistantTopBar.swift
//  FrameReply
//

import SwiftUI

struct ChatAssistantTopBar: View {
    let chat: Chat
    let onBackTap: () -> Void
    let onDetailsTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onBackTap()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.primary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Back to inbox")

            Button {
                onDetailsTap()
            } label: {
                HStack(spacing: 12) {
                    AvatarMark(
                        initials: chat.initials,
                        symbolName: chat.avatarSymbol,
                        colors: chat.gradient,
                        size: 42
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.name)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(FrameReplyColor.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open chat details for \(chat.name)")

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FrameReplyColor.outline)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 2)
    }
}
