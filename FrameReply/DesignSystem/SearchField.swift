//
//  SearchField.swift
//  FrameReply
//

import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var isActive = true

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FrameReplyColor.outlineVariant)

            TextField("Search chats...", text: $text)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .minimumScaleFactor(0.7)
                .focused($isFocused)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.82))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(FrameReplyColor.outline.opacity(0.9), lineWidth: 1.4)
                }
                .shadow(color: FrameReplyColor.primaryContainer.opacity(0.08), radius: 20, x: 0, y: 10)
        }
        .onChange(of: isActive) { _, isActive in
            if isActive == false {
                isFocused = false
            }
        }
    }
}
