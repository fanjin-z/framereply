//
//  ContactProfileCard.swift
//  zeptly
//

import SwiftUI

struct ContactProfileCard: View {
    let chat: Chat
    let subtitle: String

    private var trimmedSubtitle: String {
        subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 14) {
            AvatarMark(
                initials: chat.initials,
                symbolName: chat.avatarSymbol,
                colors: chat.gradient,
                imageData: chat.avatarData,
                size: 56,
                showsOnline: chat.isOnline
            )
            .fixedSize()

            VStack(alignment: .leading, spacing: 4) {
                Text(chat.name)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !trimmedSubtitle.isEmpty {
                    Text(trimmedSubtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurfaceVariant)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassPanel(cornerRadius: 26)
    }
}
