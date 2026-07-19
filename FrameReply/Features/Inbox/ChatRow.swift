//
//  ChatRow.swift
//  FrameReply
//

import SwiftUI

struct ChatRow: View {
    let chat: Chat
    let onChatTap: () -> Void
    let onDeleteTap: () -> Void

    var body: some View {
        Button(action: onChatTap) {
            HStack(spacing: 16) {
                AvatarMark(
                    initials: chat.initials,
                    symbolName: chat.avatarSymbol,
                    colors: chat.gradient,
                    size: 50
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(chat.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    PillChip(
                        title: chat.chipTitle,
                        symbolName: chat.chipSymbol,
                        tint: chat.isUnread ? FrameReplyColor.primaryContainer : FrameReplyColor.secondary
                    )
                    .fixedSize(horizontal: true, vertical: true)

                    Text(chat.preview)
                        .font(
                            .system(
                                size: 15,
                                weight: chat.isUnread ? .medium : .regular,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            chat.isUnread ? FrameReplyColor.onSurfaceVariant : FrameReplyColor.outline
                        )
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FrameReplyColor.outline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Chat Assistant for \(chat.name)")
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
                .fill(FrameReplyColor.primary)
                .frame(width: 5)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDeleteTap()
            } label: {
                Label("Delete Chat", systemImage: "trash")
            }
        }
    }

}
