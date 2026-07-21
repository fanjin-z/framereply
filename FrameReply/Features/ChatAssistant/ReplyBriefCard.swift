//
//  ReplyBriefCard.swift
//  FrameReply
//

import SwiftData
import SwiftUI
import UIKit

struct ReplyBriefSummaryCard: View {
    let goal: String
    let personaID: UUID?
    let onTap: () -> Void
    @Query(sort: \PersonaRecord.createdAt) private var personas: [PersonaRecord]

    private var goalSummary: String {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedGoal.isEmpty ? String(localized: "No goal set") : trimmedGoal
    }

    private var personaName: String {
        personas.first(where: { $0.id == personaID })?.name
            ?? String(localized: "Select Persona")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.primary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Reply Brief")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(FrameReplyColor.primary)

                    HStack(spacing: 6) {
                        Text(goalSummary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("•")
                            .accessibilityHidden(true)

                        Text(personaName)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FrameReplyColor.outline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(SoftPressButtonStyle())
        .glassPanel(cornerRadius: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Edit reply brief")
        .accessibilityIdentifier("reply-brief-summary")
    }

    private var accessibilityLabel: Text {
        Text("Reply Brief, Current Goal: \(goalSummary), Persona: \(personaName)")
    }
}

struct ReplyBriefDialog: View {
    @Binding var goalDraft: String
    let personaID: UUID?
    let onGoalCommit: () -> Void
    let onPersonaSelect: (UUID) -> Void
    let onDismiss: () -> Void

    @Query(sort: \PersonaRecord.createdAt) private var personas: [PersonaRecord]
    @FocusState private var isGoalFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    private var selectedPersonaName: String {
        personas.first(where: { $0.id == personaID })?.name
            ?? String(localized: "Select Persona")
    }

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = max(0, proxy.size.height - keyboardHeight)

            ZStack {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                ScrollView {
                    dialogCard
                        .frame(maxWidth: 560)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: availableHeight,
                            alignment: keyboardHeight > 0 ? .top : .center
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, keyboardHeight > 0 ? 12 : 24)
                        .padding(.bottom, keyboardHeight + 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("reply-brief-dialog")
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification
            )
        ) { notification in
            updateKeyboardHeight(from: notification)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }

    private var dialogCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            editor
        }
        .padding(20)
        .glassPanel(cornerRadius: 26)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Reply Brief")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(FrameReplyColor.onSurface)

                Text("Shape the next suggested replies")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FrameReplyColor.primary)
                    }
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityIdentifier("reply-brief-done")
        }
    }

    private func updateKeyboardHeight(from notification: Notification) {
        guard
            let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect
        else { return }

        withAnimation(.easeOut(duration: 0.25)) {
            keyboardHeight = endFrame.height
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Current Goal", systemImage: "target")
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                ChatContextField(
                    text: $goalDraft,
                    placeholder: "e.g. Agree on a time for dinner…"
                )
                .focused($isGoalFocused)
                .onSubmit(onGoalCommit)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Persona", systemImage: "theatermasks")
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                Menu {
                    ForEach(personas) { persona in
                        Button(persona.name) {
                            onPersonaSelect(persona.id)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(selectedPersonaName)
                            .font(.system(.body, design: .rounded, weight: .regular))
                            .foregroundStyle(FrameReplyColor.onSurface)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FrameReplyColor.secondaryContainer.opacity(0.28))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.36), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: isGoalFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
                onGoalCommit()
            }
        }
    }
}

private struct ReplyBriefCard_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ReplyBriefSummaryCard(
                goal: "Agree on a time for dinner",
                personaID: nil,
                onTap: {}
            )
            .previewDisplayName("Populated goal")

            ReplyBriefSummaryCard(goal: "", personaID: nil, onTap: {})
                .previewDisplayName("Empty goal")

            ReplyBriefSummaryCard(
                goal: "A deliberately long goal that should truncate safely in the summary card",
                personaID: nil,
                onTap: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .previewDisplayName("Accessibility XXXL")
        }
        .padding(24)
        .frame(width: 390)
        .background(EtherealBackground())
        .modelContainer(try! FrameReplyDataStore.makeContainer(inMemory: true))
        .previewLayout(.sizeThatFits)
    }
}
