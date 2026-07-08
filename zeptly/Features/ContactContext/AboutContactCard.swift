import SwiftUI

struct AboutContactCard: View {
    let contactName: String
    @Binding var memories: [ContactMemory]

    @State private var draft = ""
    @State private var editingMemoryID: UUID?
    @State private var editingText = ""

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeMemories: [ContactMemory] {
        memories.filter { $0.status == .active }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(symbolName: "person.text.rectangle", title: "About \(contactName)") {
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

            memoryComposer

            if activeMemories.isEmpty {
                Text("Nothing saved yet. Add a detail you would like to remember.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.outline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("contact-memory-empty-state")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(activeMemories) { memory in
                        memoryRow(memory)
                    }
                }
            }
        }
        .padding(24)
        .glassPanel(cornerRadius: 30)
    }

    private var memoryComposer: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 104)
                    .accessibilityLabel("New memory about \(contactName)")

                if draft.isEmpty {
                    Text(
                        "e.g. We met at university, she’s vegetarian, and her daughter is named Mia…"
                    )
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface.opacity(0.62))
                    .lineSpacing(4)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(RezplyColor.secondaryContainer.opacity(0.28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    }
            }

            Button(action: addMemory) {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 17)
                    .frame(height: 38)
                    .foregroundStyle(
                        trimmedDraft.isEmpty ? RezplyColor.outline : RezplyColor.primary
                    )
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.48))
                    }
            }
            .buttonStyle(SoftPressButtonStyle())
            .disabled(trimmedDraft.isEmpty)
            .accessibilityHint("Saves this as a separate memory")
        }
    }

    @ViewBuilder
    private func memoryRow(_ memory: ContactMemory) -> some View {
        if editingMemoryID == memory.id {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $editingText)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 82)
                    .accessibilityLabel("Edit memory")

                HStack {
                    Button("Delete", role: .destructive) {
                        deleteMemory(memory.id)
                    }

                    Spacer()

                    Button("Cancel") {
                        editingMemoryID = nil
                    }

                    Button("Save") {
                        saveMemory(memory.id)
                    }
                    .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .padding(14)
            .memoryRowBackground()
        } else {
            Button {
                editingMemoryID = memory.id
                editingText = memory.text
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if memory.origin == .ai {
                        Label("From conversation", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(RezplyColor.primary)
                    }

                    Text(memory.text)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .memoryRowBackground()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Memory: \(memory.text)")
            .accessibilityHint("Double tap to edit")
            .contextMenu {
                Button("Edit", systemImage: "pencil") {
                    editingMemoryID = memory.id
                    editingText = memory.text
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deleteMemory(memory.id)
                }
            }
        }
    }

    private func addMemory() {
        guard !trimmedDraft.isEmpty else { return }
        KeyboardDismissal.dismiss()
        memories.append(ContactMemory(text: trimmedDraft))
        draft = ""
    }

    private func saveMemory(_ id: UUID) {
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = memories.firstIndex(where: { $0.id == id }) else {
            return
        }
        KeyboardDismissal.dismiss()
        memories[index].text = trimmed
        memories[index].origin = .user
        memories[index].certainty = .userConfirmed
        memories[index].sourceMessageIDs = []
        memories[index].status = .active
        memories[index].updatedAt = Date()
        editingMemoryID = nil
    }

    private func deleteMemory(_ id: UUID) {
        memories.removeAll { $0.id == id }
        if editingMemoryID == id {
            editingMemoryID = nil
        }
    }
}

extension View {
    fileprivate func memoryRowBackground() -> some View {
        background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RezplyColor.secondaryContainer.opacity(0.32))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                }
        }
    }
}
