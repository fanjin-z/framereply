import SwiftUI

struct AboutContactCard: View {
    @Binding var relationshipNotes: String
    @Binding var keyFacts: [String]
    @State private var isEditingFacts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeader(symbolName: "person.text.rectangle", title: "About This Contact") {
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

            VStack(alignment: .leading, spacing: 12) {
                Text("Relationship notes")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $relationshipNotes)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(minHeight: 116)

                    if relationshipNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add notes about your history, how you met, or overarching dynamics…")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface.opacity(0.76))
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

            Divider().overlay(RezplyColor.outlineVariant.opacity(0.45))

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Key facts")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isEditingFacts.toggle()
                        }
                    } label: {
                        Label(isEditingFacts ? "Done" : "Edit", systemImage: isEditingFacts ? "checkmark" : "pencil")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(RezplyColor.primary)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(keyFacts.indices, id: \.self) { index in
                    if isEditingFacts {
                        EditableFactRow(
                            fact: Binding(
                                get: { keyFacts[index] },
                                set: { keyFacts[index] = $0 }
                            ),
                            onDelete: {
                                keyFacts.remove(at: index)
                            }
                        )
                    } else {
                        FactChip(title: keyFacts[index])
                    }
                }

                Button {
                    keyFacts.append("New fact")
                    isEditingFacts = true
                } label: {
                    Label("Add Fact", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(RezplyColor.primary)
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background {
                            Capsule(style: .continuous)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(RezplyColor.outline.opacity(0.72))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .glassPanel(cornerRadius: 30)
    }
}
