//
//  ChatContextField.swift
//  zeptly
//

import SwiftUI

struct ChatContextField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.outline)
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
            }

            TextField("", text: $text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)
                .lineLimit(1)
                .submitLabel(.done)
                .onSubmit { KeyboardDismissal.dismiss() }
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 16)
        }
        .frame(height: 48)
        .background {
            Capsule(style: .continuous)
                .fill(RezplyColor.secondaryContainer.opacity(0.28))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.36), lineWidth: 1)
                }
        }
    }
}
