//
//  ConversationUpdateControls.swift
//  FrameReply
//

import SwiftUI

struct ConversationUpdateComposer: View {
    @Binding var replyGuidance: String
    @FocusState.Binding var isGuidanceFocused: Bool
    let isImporting: Bool
    let isUpdatingReplies: Bool
    let onAddMessagesTap: () -> Void
    let onSubmitGuidance: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var dictation = GuidanceDictation()
    @State private var submissionID: UUID?
    @State private var submissionTask: Task<Void, Never>?

    private var isSubmitting: Bool { submissionID != nil }

    private var canSubmit: Bool {
        !isBusy && !isSubmitting && hasGuidance
            && (dictation.phase == .idle || dictation.phase == .listening)
            && DraftingInputLimits.canAccept(replyGuidance)
    }

    private var trimmedGuidance: String {
        replyGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasGuidance: Bool {
        !trimmedGuidance.isEmpty
    }

    private var isBusy: Bool {
        isImporting || isUpdatingReplies
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    labeledAddMessagesButton
                    guidanceField
                }
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    compactAddMessagesButton
                    guidanceField
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .onChange(of: isBusy) { _, isBusy in
            if isBusy {
                isGuidanceFocused = false
                cancelSubmission()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { cancelSubmission() }
        }
        .onDisappear { cancelSubmission() }
    }

    private var compactAddMessagesButton: some View {
        Button(action: onAddMessagesTap) {
            Group {
                if isImporting {
                    ProgressView()
                        .tint(FrameReplyColor.primary)
                } else {
                    Image(systemName: "text.below.photo")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FrameReplyColor.primary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(SoftPressButtonStyle())
        .glassEffect(
            .regular.tint(FrameReplyColor.secondaryContainer.opacity(0.82)).interactive(),
            in: Circle()
        )
        .disabled(
            isBusy || isSubmitting || dictation.isActive
                || !DraftingInputLimits.canAccept(replyGuidance)
        )
        .accessibilityLabel(isImporting ? "Importing messages" : "Add messages")
        .accessibilityHint("Opens screenshot and pasted-text import options.")
        .accessibilityIdentifier("assistant-add-messages")
    }

    private var labeledAddMessagesButton: some View {
        Button(action: onAddMessagesTap) {
            HStack(spacing: 9) {
                if isImporting {
                    ProgressView()
                        .tint(FrameReplyColor.primary)
                } else {
                    Image(systemName: "text.below.photo")
                        .font(.system(size: 17, weight: .bold))
                }

                Text(
                    isImporting
                        ? LocalizedStringResource("Importing messages…")
                        : LocalizedStringResource("Add Messages")
                )
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            }
            .foregroundStyle(FrameReplyColor.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(SoftPressButtonStyle())
        .glassEffect(
            .regular.tint(FrameReplyColor.secondaryContainer.opacity(0.82)).interactive(),
            in: Capsule(style: .continuous)
        )
        .disabled(
            isBusy || isSubmitting || dictation.isActive
                || !DraftingInputLimits.canAccept(replyGuidance)
        )
        .accessibilityHint("Opens screenshot and pasted-text import options.")
        .accessibilityIdentifier("assistant-add-messages")
    }

    private var guidanceField: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .bottom, spacing: 8) {
                ReplyGuidanceInput(
                    text: $replyGuidance,
                    isFocused: $isGuidanceFocused,
                    dictation: dictation,
                    isDisabled: isBusy,
                    isSubmitting: isSubmitting,
                    identifier: "reply-guidance-field"
                )
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )

                submitControl
            }
            .frame(maxWidth: .infinity, minHeight: 44)

            ReplyGuidanceDictationStatus(
                dictation: dictation, text: replyGuidance
            )

            if DraftingInputLimits.shouldShowCounter(for: replyGuidance) {
                Text(
                    verbatim:
                        "\(replyGuidance.count)/\(DraftingInputLimits.maximumCharacterCount)"
                )
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .monospacedDigit()
                .accessibilityLabel(
                    "\(replyGuidance.count) of "
                        + "\(DraftingInputLimits.maximumCharacterCount) characters"
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var submitControl: some View {
        Group {
            if (isUpdatingReplies || isSubmitting) && hasGuidance {
                ProgressView()
                    .tint(.white)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle().fill(FrameReplyColor.deepNavy)
                    }
                    .accessibilityLabel("Updating replies with guidance")
            } else if hasGuidance {
                Button(action: submitGuidance) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle().fill(FrameReplyColor.deepNavy)
                        }
                }
                .buttonStyle(SoftPressButtonStyle())
                .disabled(!canSubmit)
                .accessibilityLabel("Update replies with guidance")
                .accessibilityHint("Uses this guidance once to create a new set of replies.")
                .accessibilityIdentifier("submit-reply-guidance")
            } else {
                Color.clear
            }
        }
        .frame(width: 44, height: 44)
        .allowsHitTesting(hasGuidance && !isUpdatingReplies)
        .contentTransition(.opacity)
        .scaleEffect(hasGuidance ? 1 : 0.82)
        .animation(
            accessibilityReduceMotion
                ? nil
                : .spring(response: 0.24, dampingFraction: 0.84),
            value: hasGuidance
        )
    }

    private func submitGuidance() {
        guard canSubmit else { return }
        isGuidanceFocused = false
        guard dictation.isActive else {
            onSubmitGuidance()
            return
        }
        let id = UUID()
        submissionID = id
        let completion = dictation.stop()
        submissionTask = Task { @MainActor in
            defer {
                if submissionID == id {
                    submissionID = nil
                    submissionTask = nil
                }
            }
            guard let completion, case .finished(let finalText) = await completion.value,
                !Task.isCancelled, submissionID == id, !isBusy, scenePhase != .background,
                replyGuidance == finalText
            else { return }
            // The binding must be current before the parent snapshots it for generation.
            replyGuidance = finalText
            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                DraftingInputLimits.canAccept(finalText)
            else { return }
            onSubmitGuidance()
        }
    }

    private func cancelSubmission() {
        guard isSubmitting else { return }
        submissionID = nil
        submissionTask?.cancel()
        submissionTask = nil
        dictation.cancel()
    }

}
