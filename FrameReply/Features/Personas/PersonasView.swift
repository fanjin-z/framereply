import SwiftData
import SwiftUI

struct PersonasView: View {
    private let repository: PersonaRepository
    let onPersonaTap: (UUID) -> Void
    @Query(sort: \PersonaRecord.createdAt) private var records: [PersonaRecord]
    @State private var personaToDelete: PersonaRecord?
    @State private var defaultPersonaID: UUID?
    @State private var deletionError: String?
    @State private var defaultPersonaError: String?

    init(
        repository: PersonaRepository,
        onPersonaTap: @escaping (UUID) -> Void
    ) {
        self.repository = repository
        self.onPersonaTap = onPersonaTap
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
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 162)
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
                    ? LocalizedStringResource(
                        "Choose a new default. Chats using this persona will be reassigned."
                    )
                    : LocalizedStringResource(
                        "Chats using it will switch to your default persona."
                    )
            )
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

    private var deleteTitle: LocalizedStringResource {
        let personaName = personaToDelete?.name ?? String(localized: "persona")
        return "Delete \(personaName)?"
    }

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

struct CreatePersonaFloatingButton: View {
    let accessibilityIdentifier: String
    let action: () -> Void

    init(
        accessibilityIdentifier: String = "Create New Persona",
        action: @escaping () -> Void
    ) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(FrameReplyColor.primary)
                        .shadow(
                            color: FrameReplyColor.primaryContainer.opacity(0.18),
                            radius: 10,
                            x: 0,
                            y: 6
                        )
                }
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel("Create New Persona")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
