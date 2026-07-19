//
//  ConversationUpdateControls.swift
//  FrameReply
//

import SwiftUI

struct ConversationUpdateControls: View {
    let isImporting: Bool
    let hasReplyNote: Bool
    let onAddMessagesTap: () -> Void
    let onReplyNoteTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onAddMessagesTap) {
                HStack(spacing: 9) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Image(systemName: "text.below.photo")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isImporting ? "Importing…" : "Add Messages")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(FrameReplyColor.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    Capsule(style: .continuous)
                        .fill(FrameReplyColor.secondaryContainer.opacity(0.42))
                }
            }
            .buttonStyle(SoftPressButtonStyle())
            .disabled(isImporting)

            Button {
                onReplyNoteTap()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: hasReplyNote ? "checkmark.bubble" : "text.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text(hasReplyNote ? "Reply Note Added" : "Add Reply Note")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    Capsule(style: .continuous)
                        .fill(FrameReplyColor.primary)
                        .shadow(
                            color: FrameReplyColor.primaryContainer.opacity(0.28), radius: 18, x: 0,
                            y: 10)
                }
            }
            .buttonStyle(SoftPressButtonStyle())
        }
    }
}
