//
//  ConversationStrategyCard.swift
//  FrameReply
//

import SwiftUI

struct ConversationStrategyCard: View {
    let conversationStrategy: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "wand.and.stars", title: "Conversation Strategy")

            Text(conversationStrategy)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .glassPanel(cornerRadius: 24)
    }
}
