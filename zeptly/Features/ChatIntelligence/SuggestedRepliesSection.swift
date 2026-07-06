//
//  SuggestedRepliesSection.swift
//  zeptly
//

import SwiftUI

struct SuggestedRepliesSection: View {
    let replies: [SuggestedReply]
    let copiedReplyID: UUID?
    let isLoading: Bool
    let errorMessage: String?
    let onCopy: (SuggestedReply) -> Void
    let onRetry: () -> Void
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "rectangle.on.rectangle.angled", title: "Suggested Replies") {
                Button(action: onGenerate) {
                    Label(
                        replies.isEmpty ? "Generate Replies" : "Regenerate",
                        systemImage: replies.isEmpty ? "sparkles" : "arrow.clockwise"
                    )
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.primary)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }

            if isLoading && replies.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Creating replies from this conversation…")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurfaceVariant)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(cornerRadius: 24)
            } else if let errorMessage, replies.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(errorMessage)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurfaceVariant)

                    Button("Try Again", action: onRetry)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .buttonStyle(.borderedProminent)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(cornerRadius: 24)
            } else if replies.isEmpty {
                Text("Generate replies when you’re ready.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurfaceVariant)
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel(cornerRadius: 24)
            } else {
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

                if isLoading {
                    ProgressView("Refreshing replies…")
                        .font(.system(size: 13, design: .rounded))
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(RezplyColor.peach)
                }
            }
        }
    }
}
