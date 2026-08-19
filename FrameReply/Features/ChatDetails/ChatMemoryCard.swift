import SwiftData
import SwiftUI

struct ChatMemoryCard: View {
    let chat: Chat
    let memoryRecords: [ChatMemoryRecord]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            ChatDetailsSectionHeader(symbolName: "brain", title: "Remembered Context")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("chat-memory-card")

            VStack(alignment: .leading, spacing: 0) {
                if activeMemories.isEmpty {
                    Text("Nothing saved yet. Add a detail you would like to remember.")
                        .font(.callout)
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("chat-memory-empty-state")
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
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
                    .padding(12)
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    memoryComposerField

                    HStack {
                        Spacer()
                        addMemoryButton
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    memoryComposerField
                    addMemoryButton
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            FrameReplyColor.secondaryContainer.opacity(0.2),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var memoryComposerField: some View {
        TextField(
            "e.g. We met at university, they prefer vegetarian restaurants…",
            text: $draft,
            axis: .vertical
        )
        .font(.callout)
        .foregroundStyle(FrameReplyColor.onSurface)
        .lineSpacing(4)
        .lineLimit(1...4)
        .frame(minHeight: 40, alignment: .topLeading)
        .accessibilityLabel("New remembered context for \(chat.name)")
        .accessibilityIdentifier("chat-memory-composer")
    }

    private var addMemoryButton: some View {
        Button(action: addMemory) {
            Text("Add")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(
                    trimmedDraft.isEmpty ? FrameReplyColor.outline : FrameReplyColor.primary
                )
        }
        .buttonStyle(SoftPressButtonStyle())
        .disabled(trimmedDraft.isEmpty)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityHint("Saves this as a separate memory")
    }

    @ViewBuilder
    private func memoryRow(
        _ memory: ChatMemoryRecord,
        showsSeparator: Bool
    ) -> some View {
        if editingMemoryID == memory.id {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $editingText)
                    .font(.body)
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .lineSpacing(4)
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
                .font(.system(.footnote, design: .rounded, weight: .bold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
                    VStack(alignment: .leading, spacing: 7) {
                        if memory.origin == ChatMemoryOrigin.ai.rawValue {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(FrameReplyColor.primary.opacity(0.82))

                                Text("From conversation")
                                    .foregroundStyle(
                                        FrameReplyColor.onSurfaceVariant.opacity(0.88)
                                    )
                            }
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                        }

                        Text(memory.text)
                            .font(.body)
                            .foregroundStyle(FrameReplyColor.onSurface)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
