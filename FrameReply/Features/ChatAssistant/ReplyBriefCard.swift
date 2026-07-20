//
//  ReplyBriefCard.swift
//  FrameReply
//

import SwiftData
import SwiftUI

struct ReplyBriefCard: View {
    @Binding var goalDraft: String
    let personaID: UUID?
    let onGoalCommit: () -> Void
    let onPersonaSelect: (UUID) -> Void
    @Query(sort: \PersonaRecord.createdAt) private var personas: [PersonaRecord]
    @FocusState private var isGoalFocused: Bool

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 240), spacing: 16)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(symbolName: "slider.horizontal.3", title: "Reply Brief")

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Current Goal", systemImage: "target")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                    ChatContextField(
                        text: $goalDraft,
                        placeholder: "e.g. Agree on a time for dinner…"
                    )
                    .focused($isGoalFocused)
                    .onSubmit(onGoalCommit)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Persona", systemImage: "theatermasks")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                    Menu {
                        ForEach(personas) { persona in
                            Button(persona.name) {
                                onPersonaSelect(persona.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(
                                personas.first(where: { $0.id == personaID })?.name
                                    ?? "Select Persona"
                            )
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(FrameReplyColor.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

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
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 26)
        .onChange(of: isGoalFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
                onGoalCommit()
            }
        }
    }
}
