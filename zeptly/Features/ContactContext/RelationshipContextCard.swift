//
//  RelationshipContextCard.swift
//  zeptly
//

import SwiftUI

struct RelationshipContextCard: View {
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(symbolName: "hand.wave", title: "Relationship Context") {
                Text("Auto-saved")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RezplyColor.outline)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.46))
                    }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 116)

                if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add notes about your history, how you met, or overarching dynamics...")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface.opacity(0.86))
                        .lineSpacing(4)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(RezplyColor.secondaryContainer.opacity(0.28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    }
            }
        }
        .padding(24)
        .glassPanel(cornerRadius: 30)
    }
}
