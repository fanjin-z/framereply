//
//  PersonaCard.swift
//  FrameReply
//

import SwiftUI

struct PersonaCard: View {
    let persona: Persona
    let usageCount: Int
    let isDefault: Bool
    let onTap: () -> Void
    let onSetDefault: () -> Void
    let onDuplicate: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(persona.accent.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: persona.symbolName)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(persona.accent)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isDefault {
                            Circle()
                                .fill(persona.accent)
                                .frame(width: 17, height: 17)
                                .overlay {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .overlay {
                                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                                }
                                .offset(x: 2, y: 2)
                                .accessibilityHidden(true)
                        }
                    }

                Text(persona.name)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                Spacer()

                Menu {
                    if isDefault {
                        Button("Default Persona", systemImage: "checkmark.circle.fill") {}
                            .disabled(true)
                    } else {
                        Button(
                            "Set as Default", systemImage: "checkmark.circle", action: onSetDefault)
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                    if let onDelete {
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(FrameReplyColor.outline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }

            Text(persona.summary)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .lineSpacing(2)
                .foregroundStyle(FrameReplyColor.onSurfaceVariant.opacity(0.86))
                .lineLimit(2)

            if persona.learningEnabled {
                Label("Learning on \(usageCount) chats", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.outline)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isDefault ? persona.accent.opacity(0.42) : .clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityValue(isDefault ? "Default persona" : "")
    }
}
