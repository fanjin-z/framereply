//
//  ContactContextInfoGrid.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct ContactContextInfoGrid: View {
    @Binding var currentInteractionGoal: String
    @Binding var personaID: UUID
    @Binding var personaAssignedAt: Date
    @Query(sort: \PersonaRecord.createdAt) private var personas: [PersonaRecord]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 240), spacing: 16)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(symbolName: "target", title: "Current Interaction Goal")

                ContactContextField(text: $currentInteractionGoal, placeholder: "e.g., Close Q3 proposal...")
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 28)

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(symbolName: "theatermasks", title: "Preferred Persona")

                Menu {
                    ForEach(personas) { persona in
                        Button(persona.name) {
                            guard personaID != persona.id else { return }
                            personaID = persona.id
                            personaAssignedAt = Date()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(personas.first(where: { $0.id == personaID })?.name ?? "Select Persona")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.secondaryContainer.opacity(0.28))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.36), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 28)
        }
    }
}
