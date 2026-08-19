//
//  StrategyRationaleCard.swift
//  FrameReply
//

import SwiftUI

struct StrategyRationaleCard: View {
    let strategyRationale: String

    var body: some View {
        Text(strategyRationale)
            .font(.callout)
            .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                FrameReplyColor.secondaryContainer.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .glassPanel(cornerRadius: 18)
            .accessibilityIdentifier("strategy-rationale-card")
    }
}
