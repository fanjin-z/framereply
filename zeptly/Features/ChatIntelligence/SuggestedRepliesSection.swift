//
//  SuggestedRepliesSection.swift
//  zeptly
//

import SwiftUI

struct SuggestedRepliesSection: View {
    let replies: [SuggestedReply]
    let copiedReplyID: UUID?
    let onCopy: (SuggestedReply) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "rectangle.on.rectangle.angled", title: "Suggested Replies")

            VStack(spacing: 14) {
                ForEach(replies) { reply in
                    SuggestedReplyCard(
                        reply: reply,
                        isCopied: copiedReplyID == reply.id,
                        onCopy: {
                            onCopy(reply)
                        }
                    )
                }
            }
        }
    }
}
