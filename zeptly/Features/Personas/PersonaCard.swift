//
//  PersonaCard.swift
//  zeptly
//

import SwiftUI

struct PersonaCard: View {
    let persona: Persona
    let styleTags: [String]
    let usageCount: Int
    let onTap: () -> Void
    let onDuplicate: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Circle()
                    .fill(persona.accent.opacity(0.12))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: persona.symbolName)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(persona.accent)
                    }

                Spacer()

                Menu {
                    Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                    if let onDelete {
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(RezplyColor.outline)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(persona.name)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(persona.summary)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .lineSpacing(2)
                    .foregroundStyle(RezplyColor.onSurfaceVariant.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                ForEach(Array(styleTags.prefix(3).enumerated()), id: \.offset) { _, tag in
                    PillChip(title: tag, tint: RezplyColor.secondary)
                }
            }

            HStack {
                Label("\(usageCount) chats", systemImage: "message")
                Spacer()
                Label(persona.learningEnabled ? "Learning on" : "Learning off", systemImage: "sparkles")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(RezplyColor.outline)
        }
        .padding(18)
        .glassPanel(cornerRadius: 24)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
