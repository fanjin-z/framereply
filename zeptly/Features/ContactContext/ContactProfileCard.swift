//
//  ContactProfileCard.swift
//  zeptly
//

import SwiftUI

struct ContactProfileCard: View {
    let chat: Chat

    var body: some View {
        HStack(spacing: 14) {
            AvatarMark(
                initials: chat.initials,
                symbolName: chat.avatarSymbol,
                colors: chat.gradient,
                imageData: chat.avatarData,
                size: 56
            )
            .fixedSize()

            VStack(alignment: .leading, spacing: 4) {
                Text(chat.name)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassPanel(cornerRadius: 26)
    }
}
