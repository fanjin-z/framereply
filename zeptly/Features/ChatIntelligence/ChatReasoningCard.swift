//
//  ChatReasoningCard.swift
//  zeptly
//

import SwiftUI

struct ChatReasoningCard: View {
    let reasoning: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Strategy Reasoning")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(RezplyColor.outline)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(RezplyColor.primary)
                    .frame(width: 24)

                Text(reasoning)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurfaceVariant)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(RezplyColor.secondaryContainer.opacity(0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.34), lineWidth: 1)
                    }
            }
        }
    }
}
