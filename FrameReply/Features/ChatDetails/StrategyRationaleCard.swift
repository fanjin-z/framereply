//
//  StrategyRationaleCard.swift
//  FrameReply
//

import SwiftUI

struct StrategyRationaleCard: View {
    let strategyRationale: String

    var body: some View {
        Text(strategyRationale)
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 18)
            .accessibilityIdentifier("strategy-rationale-card")
    }
}
