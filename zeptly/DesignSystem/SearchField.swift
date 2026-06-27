//
//  SearchField.swift
//  zeptly
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
                .foregroundStyle(RezplyColor.outlineVariant)

            TextField("Search chats...", text: $text)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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
                        .stroke(RezplyColor.outline.opacity(0.9), lineWidth: 1.4)
                }
                .shadow(color: RezplyColor.primaryContainer.opacity(0.08), radius: 20, x: 0, y: 10)
        }
        .onChange(of: isActive) { _, isActive in
            if isActive == false {
                isFocused = false
            }
        }
    }
}
