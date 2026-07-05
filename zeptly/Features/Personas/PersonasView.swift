import SwiftData
import SwiftUI

struct PersonasView: View {
    let onPersonaTap: (UUID) -> Void
    @Query(sort: \PersonaRecord.createdAt) private var records: [PersonaRecord]
    @State private var isCreating = false
    @State private var personaToDelete: PersonaRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 12) {
                    ForEach(records) { record in
                        PersonaCard(
                            persona: record.value,
                            styleTags: ((try? PersonaRepository().promptContext(personaID: record.id))?.resolvedStyle
                                .filter { ["formality", "warmth", "length"].contains($0.dimensionKey) }
                                .map(\.shortLabel)) ?? [],
                            usageCount: (try? PersonaRepository().usageCount(personaID: record.id)) ?? 0,
                            onTap: { onPersonaTap(record.id) },
                            onDuplicate: { _ = try? PersonaRepository().duplicate(record) },
                            onDelete: record.isBuiltIn ? nil : { personaToDelete = record }
                        )
                    }
                }
                .padding(.top, 14)

                Button { isCreating = true } label: {
                    Label("Create New Persona", systemImage: "plus")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background {
                            Capsule(style: .continuous)
                                .fill(RezplyColor.primary)
                                .shadow(color: RezplyColor.primaryContainer.opacity(0.34), radius: 22, x: 0, y: 12)
                        }
                }
                .buttonStyle(SoftPressButtonStyle())
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 94)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $isCreating) {
            CreatePersonaSheet { record in
                isCreating = false
                onPersonaTap(record.id)
            }
        }
        .confirmationDialog(
            "Delete \(personaToDelete?.name ?? "persona")?",
            isPresented: Binding(
                get: { personaToDelete != nil },
                set: { if !$0 { personaToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Persona", role: .destructive) {
                if let personaToDelete { try? PersonaRepository().delete(personaToDelete) }
                personaToDelete = nil
            }
        } message: {
            Text("Chats using it will switch to The Professional.")
        }
    }
}

private struct CreatePersonaSheet: View {
    let onCreated: (PersonaRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var template: PersonaTemplate = .professional

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()
                VStack(alignment: .leading, spacing: 22) {
                    TextField("Persona name", text: $name)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .padding(16)
                        .background(RezplyColor.secondaryContainer.opacity(0.3), in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Start from")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        ForEach(PersonaTemplate.allCases, id: \.self) { option in
                            Button {
                                template = option
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                    Spacer()
                                    if template == option { Image(systemName: "checkmark.circle.fill") }
                                }
                                .foregroundStyle(RezplyColor.onSurface)
                                .padding(14)
                                .background(Color.white.opacity(template == option ? 0.62 : 0.3), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .glassPanel(cornerRadius: 26)
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("New Persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let record = try? PersonaRepository().create(name: name, template: template) {
                            onCreated(record)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
