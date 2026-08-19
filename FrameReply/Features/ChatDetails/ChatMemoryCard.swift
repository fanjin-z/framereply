import SwiftData
import SwiftUI

struct ChatMemoryCard: View {
    let chat: Chat
    let memoryRecords: [ChatMemoryRecord]

    @Environment(\.modelContext) private var modelContext
    @State private var draft = ""
    @State private var editingMemoryID: UUID?
    @State private var editingText = ""
    @State private var revealedMemoryID: UUID?
    @State private var saveError: String?

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeMemories: [ChatMemoryRecord] {
        memoryRecords.filter { $0.status == ChatMemoryStatus.active.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(symbolName: "brain", title: "Remembered Context")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("chat-memory-card")

            VStack(alignment: .leading, spacing: 0) {
                if activeMemories.isEmpty {
                    Text("Nothing saved yet. Add a detail you would like to remember.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(FrameReplyColor.outline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("chat-memory-empty-state")
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(activeMemories.enumerated()), id: \.element.id) {
                            index, memory in
                            memoryRow(
                                memory,
                                showsSeparator: index < activeMemories.count - 1
                            )
                        }
                    }
                    .background(FrameReplyColor.surfaceContainerLow)
                }

                memoryComposer
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassPanel(cornerRadius: 18)
        }
        .alert("Couldn’t Save Remembered Context", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: saveError ?? String(localized: AppStrings.Common.tryAgain))
        }
    }

    private var memoryComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                "e.g. We met at university, they prefer vegetarian restaurants…",
                text: $draft,
                axis: .vertical
            )
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(FrameReplyColor.onSurface)
            .lineSpacing(3)
            .lineLimit(1...4)
            .frame(minHeight: 40, alignment: .topLeading)
            .accessibilityLabel("New remembered context for \(chat.name)")
            .accessibilityIdentifier("chat-memory-composer")

            Button(action: addMemory) {
                Text("Add")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        trimmedDraft.isEmpty ? FrameReplyColor.outline : FrameReplyColor.primary
                    )
            }
            .buttonStyle(SoftPressButtonStyle())
            .disabled(trimmedDraft.isEmpty)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityHint("Saves this as a separate memory")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            FrameReplyColor.secondaryContainer.opacity(0.2),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    @ViewBuilder
    private func memoryRow(
        _ memory: ChatMemoryRecord,
        showsSeparator: Bool
    ) -> some View {
        if editingMemoryID == memory.id {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $editingText)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 68)
                    .accessibilityLabel("Edit memory")
                    .accessibilityIdentifier("chat-memory-editor-\(memory.id.uuidString)")

                HStack(spacing: 12) {
                    Spacer()

                    Button("Cancel") {
                        editingMemoryID = nil
                    }
                    .frame(minWidth: 72, minHeight: 44)

                    Button("Save") {
                        saveMemory(memory.id)
                    }
                    .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(minWidth: 72, minHeight: 44)
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .compactSwipeRowSurface(showsSeparator: showsSeparator)
        } else {
            CompactSwipeRow(
                isRevealed: revealedMemoryID == memory.id,
                onReveal: {
                    editingMemoryID = nil
                    revealedMemoryID = memory.id
                },
                onClose: {
                    if revealedMemoryID == memory.id {
                        revealedMemoryID = nil
                    }
                },
                onAction: {
                    deleteMemory(memory.id)
                },
                actionTitle: "Delete",
                actionSystemImage: "trash",
                actionTint: .red,
                actionAccessibilityIdentifier: "chat-memory-delete-\(memory.id.uuidString)",
                content: {
                    VStack(alignment: .leading, spacing: 4) {
                        if memory.origin == ChatMemoryOrigin.ai.rawValue {
                            Label("From conversation", systemImage: "sparkles")
                                .font(
                                    .system(size: 10, weight: .semibold, design: .rounded)
                                )
                                .foregroundStyle(FrameReplyColor.primary)
                        }

                        Text(memory.text)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(FrameReplyColor.onSurface)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if revealedMemoryID == memory.id {
                            revealedMemoryID = nil
                        } else {
                            beginEditing(memory)
                        }
                    }
                    .compactSwipeRowSurface(showsSeparator: showsSeparator)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Memory: \(memory.text)")
                    .accessibilityHint("Double tap to edit, or swipe left to delete")
                    .accessibilityIdentifier("chat-memory-row-\(memory.id.uuidString)")
                    .accessibilityAction(named: "Edit") {
                        beginEditing(memory)
                    }
                    .accessibilityAction(named: "Delete") {
                        deleteMemory(memory.id)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") {
                            beginEditing(memory)
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleteMemory(memory.id)
                        }
                    }
                }
            )
        }
    }

    private func beginEditing(_ memory: ChatMemoryRecord) {
        revealedMemoryID = nil
        editingMemoryID = memory.id
        editingText = memory.text
    }

    private func addMemory() {
        guard !trimmedDraft.isEmpty else { return }
        KeyboardDismissal.dismiss()
        modelContext.insert(
            ChatMemoryRecord(chatID: chat.id, value: ChatMemory(text: trimmedDraft))
        )
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
            revealedMemoryID = nil
        }
    }

    private func deleteMemory(_ id: UUID) {
        guard let memory = memoryRecords.first(where: { $0.id == id }) else { return }
        revealedMemoryID = nil
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
