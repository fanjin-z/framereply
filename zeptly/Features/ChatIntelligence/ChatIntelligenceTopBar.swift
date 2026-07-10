//
//  ChatIntelligenceTopBar.swift
//  zeptly
//

import SwiftUI

struct ChatIntelligenceTopBar: View {
    let chat: Chat
    let canMergeChat: Bool
    let onBackTap: () -> Void
    let onContactTap: () -> Void
    let onRenameTap: () -> Void
    let onMergeTap: () -> Void
    let onDeleteTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onBackTap()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(RezplyColor.primary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Back to inbox")

            Button {
                onContactTap()
            } label: {
                HStack(spacing: 12) {
                    AvatarMark(
                        initials: chat.initials,
                        symbolName: chat.avatarSymbol,
                        colors: chat.gradient,
                        imageData: chat.avatarData,
                        size: 42,
                        showsOnline: chat.isOnline
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.name)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open contact context for \(chat.name)")

            Spacer(minLength: 8)

            Menu {
                if chat.isProvisional {
                    Button {
                        onMergeTap()
                    } label: {
                        Label("Merge Into...", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(!canMergeChat)
                }

                Button {
                    onRenameTap()
                } label: {
                    Label("Rename Chat", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDeleteTap()
                } label: {
                    Label("Delete Chat", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(RezplyColor.primary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, 2)
    }
}
