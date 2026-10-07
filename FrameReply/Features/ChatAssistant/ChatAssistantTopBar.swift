import SwiftUI

struct ChatAssistantToolbar: ToolbarContent {
    let chat: Chat
    let isDirectChat: Bool
    let isManagementDisabled: Bool
    let onDetailsTap: () -> Void
    let onEditNamesTap: () -> Void
    let onConversationTypeTap: () -> Void
    let onDeleteTap: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button(action: onDetailsTap) {
                VStack(spacing: 2) {
                    Text(verbatim: chat.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(isDirectChat ? "Direct Chat" : "Group Chat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open chat details for \(chat.name)")
            .accessibilityValue(isDirectChat ? "Direct Chat" : "Group Chat")
            .accessibilityHint("Shows reply rationale and remembered context")
            .accessibilityIdentifier("open-chat-details")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(action: onEditNamesTap) {
                    Label(isDirectChat ? "Edit Names" : "Rename Chat", systemImage: "pencil")
                }
                Button(action: onConversationTypeTap) {
                    Label(
                        isDirectChat ? "Mark as Group Chat" : "Mark as Direct Chat",
                        systemImage: isDirectChat ? "person.2.fill" : "person.fill"
                    )
                }
                Divider()
                Button("Delete Chat", systemImage: "trash", role: .destructive, action: onDeleteTap)
            } label: {
                Label("Chat actions for \(chat.name)", systemImage: "ellipsis")
            }
            .disabled(isManagementDisabled)
            .accessibilityHint("Edit names, change conversation type, or delete this chat")
            .accessibilityIdentifier("chat-actions-menu")
        }
    }
}
