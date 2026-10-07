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
                    .fill(FrameReplyColor.fieldSurface)
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
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                Text(value)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
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

struct ReplyGoalSheet: View {
    @Binding var goalDraft: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isGoalFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(
                    "e.g. Agree on a time for dinner…",
                    text: limitedGoal,
                    axis: .vertical
                )
                .font(.body)
                .lineLimit(3...8)
                .focused($isGoalFocused)
                .accessibilityLabel("Current Goal")
                .accessibilityIdentifier("reply-brief-goal-input")
            }
            .navigationTitle("Current Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("reply-goal-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .accessibilityIdentifier("reply-goal-save")
                }
            }
            .accessibilityIdentifier("reply-goal-dialog")
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .task { isGoalFocused = true }
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
