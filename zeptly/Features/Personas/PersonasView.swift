import SwiftData
import SwiftUI

struct PersonasView: View {
    let onPersonaTap: (UUID) -> Void
    let onCreateTap: () -> Void
    @Query(sort: \PersonaRecord.createdAt) private var records: [PersonaRecord]
    @State private var personaToDelete: PersonaRecord?
    @State private var defaultPersonaID: UUID?
    @State private var deletionError: String?
    @State private var defaultPersonaError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 16) {
                    ForEach(records) { record in
                        PersonaCard(
                            persona: record.value,
                            usageCount: (try? PersonaRepository().usageCount(personaID: record.id)) ?? 0,
                            isDefault: defaultPersonaID == record.id,
                            onTap: { onPersonaTap(record.id) },
                            onSetDefault: { setDefault(record.id) },
                            onDuplicate: { _ = try? PersonaRepository().duplicate(record) },
                            onDelete: records.count > 1 ? { personaToDelete = record } : nil
                        )
                    }
                }
                .padding(.top, 14)

                Button {
                    onCreateTap()
                } label: {
                    Label("Create New Persona", systemImage: "plus")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 50)
                        .background(Capsule().fill(RezplyColor.primary))
                }
                .buttonStyle(SoftPressButtonStyle()).padding(.top, 6)
            }
            .padding(.horizontal, 24).padding(.bottom, 94)
            .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .task { defaultPersonaID = try? PersonaRepository().defaultPersonaID() }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { personaToDelete != nil },
                set: { if !$0 { personaToDelete = nil } }
            ), titleVisibility: .visible
        ) {
            if let deleting = personaToDelete, deleting.id == defaultPersonaID {
                ForEach(records.filter { $0.id != deleting.id }) { replacement in
                    Button("Use \(replacement.name) as Default", role: .destructive) {
                        delete(deleting, replacement: replacement.id)
                    }
                }
            } else {
                Button("Delete Persona", role: .destructive) {
                    if let deleting = personaToDelete { delete(deleting, replacement: nil) }
                }
            }
        } message: {
            Text(
                personaToDelete?.id == defaultPersonaID
                    ? "Choose a new default. Chats using this persona will be reassigned."
                    : "Chats using it will switch to your default persona.")
        }
        .alert(
            "Couldn’t Delete Persona",
            isPresented: Binding(
                get: { deletionError != nil }, set: { if !$0 { deletionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionError ?? "")
        }
        .alert(
            "Couldn’t Set Default Persona",
            isPresented: Binding(
                get: { defaultPersonaError != nil },
                set: { if !$0 { defaultPersonaError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(defaultPersonaError ?? "")
        }
    }

    private var deleteTitle: String { "Delete \(personaToDelete?.name ?? "persona")?" }

    private func delete(_ record: PersonaRecord, replacement: UUID?) {
        do {
            try PersonaRepository().delete(record, replacementDefaultID: replacement)
            defaultPersonaID = try PersonaRepository().defaultPersonaID()
        } catch {
            deletionError = error.localizedDescription
        }
        personaToDelete = nil
    }

    private func setDefault(_ personaID: UUID) {
        do {
            try PersonaRepository().setDefaultPersona(id: personaID)
            defaultPersonaID = personaID
        } catch {
            defaultPersonaError = error.localizedDescription
        }
    }
}
