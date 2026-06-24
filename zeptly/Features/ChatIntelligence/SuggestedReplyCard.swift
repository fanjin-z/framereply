//
//  SuggestedReplyCard.swift
//  zeptly
//

import SwiftUI

struct SuggestedReplyCard: View {
    let reply: SuggestedReply
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(reply.text)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onCopy()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background {
                    Capsule(style: .continuous)
                        .fill(RezplyColor.primary)
                }
            }
            .buttonStyle(SoftPressButtonStyle())
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(22)
        .glassPanel(cornerRadius: 24)
    }
}
