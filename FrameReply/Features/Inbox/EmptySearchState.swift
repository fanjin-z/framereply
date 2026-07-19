//
//  EmptySearchState.swift
//  FrameReply
//

import SwiftUI

struct EmptySearchState: View {
    var title = "No chats found"
    var systemImage = "bubble.left.and.text.bubble.right"
    var actionTitle: String?
    var isLoading = false
    var onAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Label(actionTitle, systemImage: "photo.on.rectangle.angled")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
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
