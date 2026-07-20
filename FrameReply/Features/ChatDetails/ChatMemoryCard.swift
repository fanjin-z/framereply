import SwiftData
import SwiftUI

struct ChatMemoryCard: View {
    let chatID: String
    let chatName: String
    let memoryRecords: [ChatMemoryRecord]

    @Environment(\.modelContext) private var modelContext
    @State private var draft = ""
    @State private var editingMemoryID: UUID?
    @State private var editingText = ""
    @State private var saveError: String?

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeMemories: [ChatMemoryRecord] {
        memoryRecords.filter { $0.status == ChatMemoryStatus.active.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(symbolName: "brain", title: "Remembered Context") {
                Text("Auto-saved")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.outline)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.46))
                    }
            }

            memoryComposer

            if activeMemories.isEmpty {
                Text("Nothing saved yet. Add a detail you would like to remember.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(FrameReplyColor.outline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chat-memory-empty-state")
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
        .alert("Couldn’t Save Remembered Context", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: saveError ?? String(localized: AppStrings.Common.tryAgain))
        }
    }

    private var memoryComposer: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 104)
                    .accessibilityLabel("New remembered context for \(chatName)")

                if draft.isEmpty {
                    Text(
                        "e.g. We met at university, they prefer vegetarian restaurants…"
                    )
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface.opacity(0.62))
                    .lineSpacing(4)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(FrameReplyColor.secondaryContainer.opacity(0.28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    }
            }

            Button(action: addMemory) {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 17)
                    .frame(minHeight: 38)
                    .foregroundStyle(
                        trimmedDraft.isEmpty ? FrameReplyColor.outline : FrameReplyColor.primary
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
    private func memoryRow(_ memory: ChatMemoryRecord) -> some View {
        if editingMemoryID == memory.id {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $editingText)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
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
                    if memory.origin == ChatMemoryOrigin.ai.rawValue {
                        Label("From conversation", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(FrameReplyColor.primary)
                    }

                    Text(memory.text)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurface)
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
        modelContext.insert(ChatMemoryRecord(chatID: chatID, value: ChatMemory(text: trimmedDraft)))
        if save() {
            draft = ""
        }
    }

    private func saveMemory(_ id: UUID) {
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let memory = memoryRecords.first(where: { $0.id == id })
        else {
            return
        }
        KeyboardDismissal.dismiss()
        memory.update(
            from: ChatMemory(
                id: memory.id,
                text: trimmed,
                origin: .user,
                certainty: .userConfirmed,
                status: .active,
                createdAt: memory.createdAt,
                updatedAt: Date()
            )
        )
        if save() {
            editingMemoryID = nil
        }
    }

    private func deleteMemory(_ id: UUID) {
        guard let memory = memoryRecords.first(where: { $0.id == id }) else { return }
        modelContext.delete(memory)
        _ = save()
        if editingMemoryID == id {
            editingMemoryID = nil
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
            return false
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }
}

extension View {
    fileprivate func memoryRowBackground() -> some View {
        background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FrameReplyColor.secondaryContainer.opacity(0.32))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                }
        }
    }
}
