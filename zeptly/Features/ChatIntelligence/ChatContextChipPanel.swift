//
//  ChatContextChipPanel.swift
//  zeptly
//

import SwiftUI

struct ChatContextChipPanel: View {
    let chips: [String]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 126), spacing: 10, alignment: .leading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(chips, id: \.self) { chip in
                PillChip(title: chip, symbolName: symbol(for: chip), tint: RezplyColor.primary)
                    .fixedSize(horizontal: true, vertical: true)
            }

            Button {
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RezplyColor.onSurface)
                    .frame(width: 48, height: 48)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.72))
                            .shadow(color: RezplyColor.primaryContainer.opacity(0.12), radius: 16, x: 0, y: 8)
                    }
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Edit chat intelligence")
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .glassPanel(cornerRadius: 30)
    }

    private func symbol(for chip: String) -> String {
        if chip.localizedCaseInsensitiveContains("schedule") {
            return "flag"
        }
        if chip.localizedCaseInsensitiveContains("professional") {
            return "person.crop.circle.badge.checkmark"
        }
        if chip.localizedCaseInsensitiveContains("creative") {
            return "sparkles"
        }
        return "lightbulb"
    }
}
