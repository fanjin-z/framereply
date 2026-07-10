//
//  ChatRow.swift
//  zeptly
//

import SwiftUI

struct ChatRow: View {
    let chat: Chat
    let onChatTap: () -> Void
    let onAvatarTap: () -> Void
    let onDeleteTap: () -> Void

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
                    }

                    PillChip(
                        title: chat.chipTitle,
                        symbolName: chat.chipSymbol,
                        tint: chat.isUnread ? RezplyColor.primaryContainer : RezplyColor.secondary
                    )
                    .fixedSize(horizontal: true, vertical: true)

                    Text(chat.preview)
                        .font(
                            .system(
                                size: 15, weight: chat.isUnread ? .medium : .regular,
                                design: .rounded)
                        )
                        .foregroundStyle(
                            chat.isUnread ? RezplyColor.onSurfaceVariant : RezplyColor.outline
                        )
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
        .contextMenu {
            Button(role: .destructive) {
                onDeleteTap()
            } label: {
                Label("Delete Chat", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        let mark = AvatarMark(
            initials: chat.initials,
            symbolName: chat.avatarSymbol,
            colors: chat.gradient,
            imageData: chat.avatarData,
            size: 50
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
