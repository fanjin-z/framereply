//
//  ChatIntelligenceTopBar.swift
//  zeptly
//

import SwiftUI

struct ChatIntelligenceTopBar: View {
    let chat: Chat
    let onBackTap: () -> Void
    let onContactTap: () -> Void

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
                        size: 42,
                        showsOnline: chat.isOnline
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.name)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(chat.isOnline ? "Online" : "Chat Intel")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open contact context for \(chat.name)")

            Spacer(minLength: 8)

            Button {
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
