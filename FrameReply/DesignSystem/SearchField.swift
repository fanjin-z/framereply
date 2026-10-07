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
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)

            TextField("Search chats...", text: $text)
                .font(.system(.body, design: .rounded, weight: .regular))
                .foregroundStyle(FrameReplyColor.onSurface)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .minimumScaleFactor(0.7)
                .focused($isFocused)
                .accessibilityIdentifier("chats-search-field")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("clear-chat-search")
                .transition(.opacity)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, text.isEmpty ? 16 : 2)
        .frame(minHeight: 46)
        .background {
            Capsule(style: .continuous)
                .fill(FrameReplyColor.fieldSurface)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            FrameReplyColor.outlineVariant.opacity(0.58),
                            lineWidth: 1
                        )
                }
        }
        .onChange(of: isActive) { _, isActive in
            if isActive == false {
                isFocused = false
            }
        }
    }
}
