//
//  ConversationStrategyCard.swift
//  FrameReply
//

import SwiftUI

struct ConversationStrategyCard: View {
    let conversationStrategy: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(symbolName: "wand.and.stars", title: "Conversation Strategy")

            Text(conversationStrategy)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(cornerRadius: 18)
                .accessibilityIdentifier("conversation-strategy-card")
        }
    }
}
