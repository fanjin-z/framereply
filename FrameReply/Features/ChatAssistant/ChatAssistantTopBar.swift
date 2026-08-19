//
//  ChatAssistantTopBar.swift
//  FrameReply
//

import SwiftUI

struct ChatAssistantTopBar: View {
    let chat: Chat
    let isDirectChat: Bool
    let isManagementDisabled: Bool
    let onBackTap: () -> Void
    let onDetailsTap: () -> Void
    let onEditNamesTap: () -> Void
    let onConversationTypeTap: () -> Void
    let onDeleteTap: () -> Void

    var body: some View {
        FrameReplyTopBar {
            HStack(spacing: 12) {
                FrameReplyTopBarBackButton(
                    accessibilityLabel: "Back to chats",
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

                        VStack(alignment: .leading, spacing: 1) {
                            Text(chat.name)
                                .font(.system(size: 19, weight: .semibold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurface)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Text(isDirectChat ? "Direct Chat" : "Group Chat")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Open chat details for \(chat.name)")
                .accessibilityValue(isDirectChat ? "Direct Chat" : "Group Chat")
                .accessibilityHint("Shows reply rationale and remembered context")
                .accessibilityIdentifier("open-chat-details")

                Menu {
                    Button(action: onEditNamesTap) {
                        Label(
                            isDirectChat ? "Edit Names" : "Rename Chat",
                            systemImage: "pencil"
                        )
                    }

                    Button(action: onConversationTypeTap) {
                        Label(
                            isDirectChat ? "Mark as Group Chat" : "Mark as Direct Chat",
                            systemImage: isDirectChat ? "person.2.fill" : "person.fill"
                        )
                    }

                    Divider()

                    Button(role: .destructive, action: onDeleteTap) {
                        Label("Delete Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FrameReplyColor.primary)
                        .frame(width: 38, height: 38)
                        .background {
                            Circle()
                                .fill(Color.white.opacity(0.62))
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isManagementDisabled)
                .opacity(isManagementDisabled ? 0.5 : 1)
                .accessibilityLabel("Chat actions for \(chat.name)")
                .accessibilityHint("Edit names, change conversation type, or delete this chat")
                .accessibilityIdentifier("chat-actions-menu")
            }
        }
    }
}
