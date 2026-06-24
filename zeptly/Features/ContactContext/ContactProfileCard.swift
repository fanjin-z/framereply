//
//  ContactProfileCard.swift
//  zeptly
//

import SwiftUI

struct ContactProfileCard: View {
    let chat: Chat
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            AvatarMark(
                initials: chat.initials,
                symbolName: chat.avatarSymbol,
                colors: chat.gradient,
                size: 96,
                showsOnline: chat.isOnline
            )
            .padding(.top, 8)

            VStack(spacing: 7) {
                Text(chat.name)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(subtitle)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .glassPanel(cornerRadius: 34)
    }
}
