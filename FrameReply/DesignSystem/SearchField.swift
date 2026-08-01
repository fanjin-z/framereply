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
                .accessibilityIdentifier("chats-search-field")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FrameReplyColor.outlineVariant)
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
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.46))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            FrameReplyColor.outlineVariant.opacity(0.58),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: FrameReplyColor.primaryContainer.opacity(0.08),
                    radius: 12,
                    x: 0,
                    y: 6
                )
        }
        .onChange(of: isActive) { _, isActive in
            if isActive == false {
                isFocused = false
            }
        }
    }
}
