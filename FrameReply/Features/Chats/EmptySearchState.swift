//
//  EmptySearchState.swift
//  FrameReply
//

import SwiftUI

struct EmptySearchState: View {
    var title: LocalizedStringResource = "No chats found"
    var systemImage = "bubble.left.and.text.bubble.right"
    var actionTitle: LocalizedStringResource?
    var isLoading = false
    var onAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
            Text(title)
                .font(.system(.body, design: .rounded, weight: .semibold))

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Label {
                        Text(actionTitle)
                    } icon: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
        }
        .foregroundStyle(FrameReplyColor.outline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .glassPanel(cornerRadius: 26)
    }
}
