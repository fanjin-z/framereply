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
        FrameReplyTopBar {
            HStack(spacing: 12) {
                FrameReplyTopBarBackButton(
                    accessibilityLabel: "Back to inbox",
                    action: onBackTap
                )

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

                        Text(chat.name)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(FrameReplyColor.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Open chat details for \(chat.name)")
                .accessibilityHint("Shows chat settings and memory")
                .accessibilityIdentifier("open-chat-details")
            }
        }
    }
}
