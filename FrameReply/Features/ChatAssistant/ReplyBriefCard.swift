//
//  ReplyBriefCard.swift
//  FrameReply
//

import SwiftData
import SwiftUI

struct ReplyBriefSummaryCard: View {
    let goal: String
    let personaID: UUID?
    let onGoalTap: () -> Void
    let onPersonaSelect: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(symbolName: "slider.horizontal.3", title: "Reply Brief")
                .accessibilityIdentifier("reply-brief-summary")

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        goalSection
                        Divider()
                            .overlay(FrameReplyColor.outlineVariant.opacity(0.42))
                        personaSection
                    }
                } else {
                    HStack(spacing: 0) {
                        goalSection
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider()
                            .overlay(FrameReplyColor.outlineVariant.opacity(0.42))

                        personaSection
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.46))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    private var goalSection: some View {
        Button(action: onGoalTap) {
            briefSectionLabel(
                title: "Current Goal",
                value: goalSummary,
                symbolName: "target",
                trailingSymbolName: "chevron.right"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current Goal: \(goalSummary)")
        .accessibilityHint("Opens the current goal editor")
        .accessibilityIdentifier("reply-brief-goal")
    }

    private var personaSection: some View {
        Menu {
            ForEach(personas) { persona in
                Button {
                    onPersonaSelect(persona.id)
                } label: {
                    if persona.id == personaID {
                        Label(persona.name, systemImage: "checkmark")
                    } else {
                        Text(persona.name)
                    }
                }
            }
        } label: {
            briefSectionLabel(
                title: "Persona",
                value: personaName,
                symbolName: "theatermasks",
                trailingSymbolName: "chevron.down"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Persona: \(personaName)")
        .accessibilityHint("Chooses the persona for this chat")
        .accessibilityIdentifier("reply-brief-persona")
    }

    private func briefSectionLabel(
        title: LocalizedStringResource,
        value: String,
        symbolName: String,
        trailingSymbolName: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FrameReplyColor.primary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: trailingSymbolName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FrameReplyColor.outline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
    }

}

struct ReplyGoalDialog: View {
    @Binding var goalDraft: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @FocusState private var isGoalFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Current Goal Editor")
                .accessibilityIdentifier("reply-goal-dialog")

            VStack {
                Spacer(minLength: 20)
                dialogCard
                    .frame(maxWidth: 560)
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            Task { @MainActor in
                isGoalFocused = true
            }
        }
    }

    private var dialogCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Current Goal", systemImage: "target")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(FrameReplyColor.onSurface)

            TextField(
                "e.g. Agree on a time for dinner…",
                text: limitedGoal,
                axis: .vertical
            )
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(FrameReplyColor.onSurface)
            .lineLimit(3...5)
            .submitLabel(.done)
            .focused($isGoalFocused)
            .onSubmit(onSave)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FrameReplyColor.secondaryContainer.opacity(0.28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.46), lineWidth: 1)
                    }
            }
            .accessibilityLabel("Current Goal")
            .accessibilityIdentifier("reply-brief-goal-input")

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FrameReplyColor.secondaryContainer.opacity(0.38))
                    }
                    .buttonStyle(SoftPressButtonStyle())
                    .accessibilityIdentifier("reply-goal-cancel")

                Button("Save", action: onSave)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FrameReplyColor.primary)
                    }
                    .buttonStyle(SoftPressButtonStyle())
                    .accessibilityIdentifier("reply-goal-save")
            }
        }
        .padding(20)
        .glassPanel(cornerRadius: 24)
    }

    private var limitedGoal: Binding<String> {
        Binding(
            get: { goalDraft },
            set: { goalDraft = String($0.prefix(500)) }
        )
    }
}

private struct ReplyBriefCard_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ReplyBriefSummaryCard(
                goal: "Agree on a time for dinner",
                personaID: nil,
                onGoalTap: {},
                onPersonaSelect: { _ in }
            )
            .previewDisplayName("Populated goal")

            ReplyBriefSummaryCard(
                goal: "",
                personaID: nil,
                onGoalTap: {},
                onPersonaSelect: { _ in }
            )
            .previewDisplayName("Empty goal")

            ReplyBriefSummaryCard(
                goal: "A deliberately long goal that should truncate safely in the summary card",
                personaID: nil,
                onGoalTap: {},
                onPersonaSelect: { _ in }
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .previewDisplayName("Accessibility XXXL")
        }
        .padding(16)
        .frame(width: 390)
        .background(EtherealBackground())
        .modelContainer(try! FrameReplyDataStore.makeContainer(inMemory: true))
        .previewLayout(.sizeThatFits)
    }
}
