//
//  SuggestedActionCard.swift
//  zeptly
//

import SwiftUI

struct SuggestedActionCard: View {
    let action: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "wand.and.stars", title: "Suggested Next Step")

            Text(action)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .glassPanel(cornerRadius: 24)
    }
}
