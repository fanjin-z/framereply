//
//  StrategyRationaleCard.swift
//  zeptly
//

import SwiftUI

struct StrategyRationaleCard: View {
    let strategyRationale: String
    let generatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "sparkles", title: "Why These Replies") {
                Text(generatedAt, style: .relative)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RezplyColor.outline)
            }

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "lightbulb.max")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(RezplyColor.primary)
                    .frame(width: 24)

                Text(strategyRationale)
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
