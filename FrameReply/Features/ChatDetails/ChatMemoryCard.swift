import SwiftData
import SwiftUI
import UIKit

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
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "brain", title: "Remembered Context")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("chat-memory-card")
                .padding(.horizontal, 22)
                .padding(.top, 22)

            if activeMemories.isEmpty {
                Text("Nothing saved yet. Add a detail you would like to remember.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(FrameReplyColor.outline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chat-memory-empty-state")
                    .padding(.horizontal, 22)
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
                .clipped()
            }

            memoryComposer
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
        }
        .glassPanel(cornerRadius: 28)
        .alert("Couldn’t Save Remembered Context", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: saveError ?? String(localized: AppStrings.Common.tryAgain))
        }
    }

    private var memoryComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "e.g. We met at university, they prefer vegetarian restaurants…",
                text: $draft,
                axis: .vertical
            )
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(FrameReplyColor.onSurface)
            .lineSpacing(4)
            .lineLimit(1...)
            .frame(minHeight: 42, alignment: .topLeading)
            .accessibilityLabel("New remembered context for \(chat.name)")

            Button(action: addMemory) {
                Text("Add")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        trimmedDraft.isEmpty ? FrameReplyColor.outline : FrameReplyColor.primary
                    )
            }
            .buttonStyle(SoftPressButtonStyle())
            .disabled(trimmedDraft.isEmpty)
            .accessibilityHint("Saves this as a separate memory")
        }
        .padding(14)
        .background(
            FrameReplyColor.secondaryContainer.opacity(0.2),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
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
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .compactMemoryRowSurface(showsSeparator: showsSeparator)
        } else {
            CompactMemorySwipeRow(
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
                onDelete: {
                    deleteMemory(memory.id)
                },
                deleteAccessibilityIdentifier: "chat-memory-delete-\(memory.id.uuidString)"
            ) {
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
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    if revealedMemoryID == memory.id {
                        revealedMemoryID = nil
                    } else {
                        beginEditing(memory)
                    }
                }
                .compactMemoryRowSurface(showsSeparator: showsSeparator)
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

extension View {
    fileprivate func compactMemoryRowSurface(showsSeparator: Bool) -> some View {
        background(FrameReplyColor.surfaceContainerLow)
            .overlay(alignment: .bottom) {
                if showsSeparator {
                    Rectangle()
                        .fill(FrameReplyColor.outlineVariant.opacity(0.55))
                        .frame(height: 0.5)
                        .padding(.horizontal, 22)
                }
            }
    }
}

private struct CompactMemorySwipeRow<Content: View>: View {
    private let actionWidth: CGFloat = 82
    private let swipeProjectionTime: CGFloat = 0.2

    let isRevealed: Bool
    let onReveal: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void
    let deleteAccessibilityIdentifier: String
    let content: Content

    @State private var dragTranslation: CGFloat = 0

    init(
        isRevealed: Bool,
        onReveal: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        deleteAccessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.isRevealed = isRevealed
        self.onReveal = onReveal
        self.onClose = onClose
        self.onDelete = onDelete
        self.deleteAccessibilityIdentifier = deleteAccessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onDelete) {
                VStack(spacing: 3) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Delete")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
            }
            .buttonStyle(.plain)
            .opacity(isActionVisible ? 1 : 0)
            .allowsHitTesting(isRevealed)
            .accessibilityHidden(!isRevealed)
            .accessibilityIdentifier(deleteAccessibilityIdentifier)

            content
                .offset(x: rowOffset)
                .gesture(
                    HorizontalPanGesture(
                        onChanged: { translation in
                            dragTranslation = translation
                        },
                        onEnded: finishSwipe,
                        onCancelled: {
                            dragTranslation = 0
                        }
                    )
                )
        }
        .background(alignment: .trailing) {
            Color.red
                .opacity(isActionVisible ? 1 : 0)
                .frame(width: actionWidth)
        }
        .background(FrameReplyColor.surfaceContainerLow)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.2), value: isRevealed)
    }

    private var isActionVisible: Bool {
        isRevealed || dragTranslation < 0
    }

    private var rowOffset: CGFloat {
        let restingOffset = isRevealed ? -actionWidth : 0
        return min(0, max(-actionWidth, restingOffset + dragTranslation))
    }

    private func finishSwipe(translation: CGFloat, velocity: CGFloat) {
        let restingOffset = isRevealed ? -actionWidth : 0
        let projectedTranslation = translation + velocity * swipeProjectionTime
        let projectedOffset = min(
            0,
            max(-actionWidth, restingOffset + projectedTranslation)
        )

        dragTranslation = 0
        if projectedOffset < -actionWidth / 2 {
            onReveal()
        } else {
            onClose()
        }
    }
}

/// A pan gesture that fails before recognition unless the user's movement is
/// predominantly horizontal. Failing early leaves vertical drags to the
/// enclosing chat-details scroll view.
private struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
    let onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        let translation = recognizer.translation(in: recognizer.view).x

        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
                return false
            }

            let velocity = panGesture.velocity(in: panGesture.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }
    }
}
