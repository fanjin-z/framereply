//
//  KeyFactsCard.swift
//  zeptly
//

import SwiftUI

struct KeyFactsCard: View {
    @Binding var facts: [String]
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(symbolName: "key", title: "Key Facts") {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isEditing.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 12, weight: .bold))
                        Text(isEditing ? "Done" : "Edit")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(RezplyColor.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.primaryContainer.opacity(0.16))
                            .shadow(color: RezplyColor.primaryContainer.opacity(0.18), radius: 12, x: 0, y: 6)
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
            }

            VStack(alignment: .leading, spacing: 11) {
                ForEach(facts.indices, id: \.self) { index in
                    if isEditing {
                        EditableFactRow(
                            fact: Binding(
                                get: { facts[index] },
                                set: { facts[index] = $0 }
                            ),
                            onDelete: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    facts = facts.enumerated()
                                        .filter { $0.offset != index }
                                        .map(\.element)
                                }
                            }
                        )
                    } else {
                        FactChip(title: facts[index])
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        facts.append("New fact")
                        isEditing = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Add Fact")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(RezplyColor.primary)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background {
                        Capsule(style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(RezplyColor.outline.opacity(0.72))
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .padding(.top, 2)
            }
        }
        .padding(24)
        .glassPanel(cornerRadius: 30)
    }
}
