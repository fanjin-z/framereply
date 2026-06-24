//
//  EditableFactRow.swift
//  zeptly
//

import SwiftUI

struct EditableFactRow: View {
    @Binding var fact: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Fact", text: $fact)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)
                .textInputAutocapitalization(.sentences)

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(RezplyColor.outline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete fact")
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background {
            Capsule(style: .continuous)
                .fill(RezplyColor.secondaryContainer.opacity(0.32))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                }
        }
    }
}
