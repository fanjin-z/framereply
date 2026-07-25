import SwiftData
import SwiftUI

struct PersonasView: View {
    private let repository: PersonaRepository
    let onPersonaTap: (UUID) -> Void
    let onCreateTap: () -> Void
    @Query(sort: \PersonaRecord.createdAt) private var records: [PersonaRecord]
    @State private var personaToDelete: PersonaRecord?
    @State private var defaultPersonaID: UUID?
    @State private var deletionError: String?
    @State private var defaultPersonaError: String?

    init(
        repository: PersonaRepository,
        onPersonaTap: @escaping (UUID) -> Void,
        onCreateTap: @escaping () -> Void
    ) {
        self.repository = repository
        self.onPersonaTap = onPersonaTap
        self.onCreateTap = onCreateTap
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 16) {
                    ForEach(records) { record in
                        PersonaCard(
                            persona: record.value,
                            usageCount: (try? repository.usageCount(personaID: record.id))
                                ?? 0,
                            isDefault: defaultPersonaID == record.id,
                            onTap: { onPersonaTap(record.id) },
                            onSetDefault: { setDefault(record.id) },
                            onDuplicate: { _ = try? repository.duplicate(record) },
                            onDelete: records.count > 1 ? { personaToDelete = record } : nil
                        )
                        .accessibilityIdentifier(personaCardIdentifier(record))
                    }
                }
                .padding(.top, 14)

                Button {
                    onCreateTap()
                } label: {
                    Label("Create New Persona", systemImage: "plus")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 50)
                        .background(Capsule().fill(FrameReplyColor.primary))
                }
                .buttonStyle(SoftPressButtonStyle()).padding(.top, 6)
            }
            .padding(.horizontal, 24).padding(.bottom, 94)
            .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("personas-screen")
        .task { defaultPersonaID = try? repository.defaultPersonaID() }
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

    private func personaCardIdentifier(_ record: PersonaRecord) -> String {
        if let builtInID = record.builtInID {
            return "persona-card-\(builtInID.rawValue)"
        }
        return "persona-card-\(record.id.uuidString.lowercased())"
    }

    private func delete(_ record: PersonaRecord, replacement: UUID?) {
        do {
            try repository.delete(record, replacementDefaultID: replacement)
            defaultPersonaID = try repository.defaultPersonaID()
        } catch {
            deletionError = error.localizedDescription
        }
        personaToDelete = nil
    }

    private func setDefault(_ personaID: UUID) {
        do {
            try repository.setDefaultPersona(id: personaID)
            defaultPersonaID = personaID
        } catch {
            defaultPersonaError = error.localizedDescription
        }
    }
}
