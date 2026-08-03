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
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .onChange(of: isBusy) { _, isBusy in
            if isBusy {
                isGuidanceFocused = false
            }
        }
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
        .disabled(isBusy)
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
                .font(.system(size: 15, weight: .bold, design: .rounded))
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
        .disabled(isBusy)
        .accessibilityHint("Opens screenshot and pasted-text import options.")
        .accessibilityIdentifier("assistant-add-messages")
    }

    private var guidanceField: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .bottom, spacing: 4) {
                TextField(
                    "Add reply guidance…",
                    text: limitedGuidance,
                    axis: .vertical
                )
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
                .lineLimit(1...3)
                .submitLabel(.return)
                .disabled(isBusy)
                .focused($isGuidanceFocused)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .contentShape(.interaction, Rectangle())
                .accessibilityLabel("Reply Guidance")
                .accessibilityHint(
                    "One-use context, direction, tone, or a rough draft for the next replies."
                )
                .accessibilityIdentifier("reply-guidance-field")

                submitControl
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(
                .interaction,
                RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .onTapGesture {
                guard !isBusy, !hasGuidance else { return }
                isGuidanceFocused = true
            }
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )

            if DraftingInputLimits.shouldShowCounter(for: replyGuidance) {
                Text("\(replyGuidance.count)/\(DraftingInputLimits.maximumCharacterCount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
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
            if isUpdatingReplies && hasGuidance {
                ProgressView()
                    .tint(.white)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle().fill(FrameReplyColor.deepNavy)
                    }
                    .accessibilityLabel("Updating replies with guidance")
            } else if hasGuidance {
                Button(action: onSubmitGuidance) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background {
                            Circle().fill(FrameReplyColor.deepNavy)
                        }
                }
                .buttonStyle(SoftPressButtonStyle())
                .disabled(isBusy || !hasGuidance)
                .accessibilityLabel("Update replies with guidance")
                .accessibilityHint("Uses this guidance once to create a new set of replies.")
                .accessibilityIdentifier("submit-reply-guidance")
            } else {
                Color.clear
            }
        }
        .frame(width: 36, height: 36)
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

    private var limitedGuidance: Binding<String> {
        Binding(
            get: { replyGuidance },
            set: { newValue in
                guard DraftingInputLimits.canAccept(newValue) else {
                    return
                }
                replyGuidance = newValue
            }
        )
    }
}
