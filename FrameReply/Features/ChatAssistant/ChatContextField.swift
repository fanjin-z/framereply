//
//  ChatContextField.swift
//  FrameReply
//

import SwiftUI

struct ChatContextField: View {
    @Binding var text: String
    let placeholder: LocalizedStringResource

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(FrameReplyColor.outline)
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
            }

            TextField("", text: $text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
                .lineLimit(1)
                .submitLabel(.done)
                .onSubmit { KeyboardDismissal.dismiss() }
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 16)
        }
        .frame(minHeight: 48)
        .background {
            Capsule(style: .continuous)
                .fill(FrameReplyColor.secondaryContainer.opacity(0.28))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.36), lineWidth: 1)
                }
        }
    }
}
