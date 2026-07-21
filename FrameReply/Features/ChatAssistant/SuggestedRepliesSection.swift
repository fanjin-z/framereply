//
//  SuggestedRepliesSection.swift
//  FrameReply
//

import SwiftUI

struct SuggestedRepliesSection: View {
    let replies: [SuggestedReply]
    let copiedReplyID: UUID?
    let isLoading: Bool
    let needsRefresh: Bool
    let errorMessage: String?
    let onCopy: (SuggestedReply) -> Void
    let onRetry: () -> Void
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "rectangle.on.rectangle.angled", title: "Suggested Replies") {
                if replies.isEmpty || needsRefresh {
                    Button(action: onGenerate) {
                        Label(
                            replies.isEmpty ? "Generate Replies" : "Update Replies",
                            systemImage: "sparkles"
                        )
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
            }

            if isLoading && replies.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Creating replies from this conversation…")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(cornerRadius: 24)
            } else if let errorMessage, replies.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(errorMessage)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)

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
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
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

                if needsRefresh && !isLoading {
                    Label(
                        "The reply brief changed. Update when you’re ready.",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }

                if isLoading {
                    ProgressView("Refreshing replies…")
                        .font(.system(size: 13, design: .rounded))
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(FrameReplyColor.peach)
                }
            }
        }
        .accessibilityIdentifier("suggested-replies-section")
    }
}
