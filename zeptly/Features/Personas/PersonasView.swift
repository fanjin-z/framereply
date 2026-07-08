import SwiftData
import SwiftUI

struct PersonasView: View {
    @ObservedObject var providerStore: ProviderStore
    let onPersonaTap: (UUID) -> Void
    @Query(sort: \PersonaRecord.createdAt) private var records: [PersonaRecord]
    @State private var isCreating = false
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
                    isCreating = true
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
        .sheet(isPresented: $isCreating) {
            CreatePersonaSheet(providerStore: providerStore) { record in
                isCreating = false
                onPersonaTap(record.id)
            }
        }
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

private struct CreatePersonaSheet: View {
    @ObservedObject var providerStore: ProviderStore
    let onCreated: (PersonaRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PersonaRecord.createdAt) private var personas: [PersonaRecord]
    @Query private var storedObservations: [PersonaObservationRecord]
    @State private var step = 0
    @State private var name = ""
    @State private var summary = ""
    @State private var instructions = ""
    @State private var basePersonaID: UUID?
    @State private var selections: [String: Int] = [:]
    @State private var draftObservations: [PersonaObservation] = []
    @State private var examples = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(["Basics", "Quick Style", "Teach It Your Voice", "Review"][step])
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                        ProgressView(value: Double(step + 1), total: 4)
                        stepContent
                    }
                    .padding(24)
                }
            }
            .navigationTitle("New Persona").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        KeyboardDismissal.dismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        if step > 0 {
                            Button("Back") {
                                KeyboardDismissal.dismiss()
                                step -= 1
                            }
                        }
                        Spacer()
                        if step < 3 {
                            Button("Next") {
                                KeyboardDismissal.dismiss()
                                advance()
                            }.disabled(step == 0 && trimmedName.isEmpty)
                        } else {
                            Button("Create") {
                                KeyboardDismissal.dismiss()
                                create()
                            }.disabled(trimmedName.isEmpty)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: basics
        case 1: quickStyle
        case 2: teachVoice
        default: review
        }
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Persona name", text: $name)
            field("Short summary", text: $summary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Start from").font(.headline)
                Picker("Start from", selection: $basePersonaID) {
                    Text("Blank").tag(UUID?.none)
                    ForEach(personas) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu).onChange(of: basePersonaID) { _, value in selectBase(value) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions").font(.headline)
                TextEditor(text: $instructions).frame(minHeight: 150).editorPanel()
            }
        }
    }

    private var quickStyle: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Optional shortcuts. These become normal observations after creation.")
                .font(.subheadline).foregroundStyle(RezplyColor.outline)
            ForEach(PersonaQuickSetup.dimensions) { dimension in
                let selection = selections[dimension.id] ?? 0
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(dimension.title).font(.headline)
                        Spacer()
                        Text(dimension.label(for: selection))
                    }
                    Picker(
                        dimension.title,
                        selection: Binding(
                            get: { selections[dimension.id] ?? 0 },
                            set: { selections[dimension.id] = $0 }
                        )
                    ) {
                        ForEach(-2...2, id: \.self) { Text(dimension.label(for: $0)).tag($0) }
                    }.pickerStyle(.segmented)
                }.padding(16).glassPanel(cornerRadius: 20)
            }
        }
    }

    private var teachVoice: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Optional: paste 3–10 messages you wrote, one per line. Examples are discarded after analysis.")
                .font(.subheadline).foregroundStyle(RezplyColor.outline)
            TextEditor(text: $examples).frame(minHeight: 180).editorPanel()
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            Button(isAnalyzing ? "Analyzing…" : "Analyze Examples") { analyzeExamples() }
                .buttonStyle(SoftPressButtonStyle())
                .disabled(!(3...10).contains(exampleLines.count) || isAnalyzing)
            if draftObservations.contains(where: { $0.evidenceSource == .examples }) {
                Label("Writing examples analyzed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(RezplyColor.primary)
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(trimmedName).font(.title2.bold())
            if !summary.isEmpty { Text(summary).foregroundStyle(RezplyColor.outline) }
            Text("Instructions").font(.headline)
            TextEditor(text: $instructions).frame(minHeight: 120).editorPanel()
            HStack {
                Text("Observations").font(.headline)
                Spacer()
                Text("\(draftObservations.count)/20")
            }
            ForEach(Array(draftObservations.indices), id: \.self) { index in
                HStack(alignment: .top) {
                    TextField(
                        "Observation",
                        text: Binding(
                            get: { draftObservations[index].text },
                            set: {
                                draftObservations[index].text = $0
                                draftObservations[index].origin = .user
                                draftObservations[index].isUserProtected = true
                                draftObservations[index].evidenceSource = .user
                            }
                        ), axis: .vertical)
                    Button(role: .destructive) {
                        draftObservations.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                }.padding(14).glassPanel(cornerRadius: 18)
            }
            Button("Add Observation", systemImage: "plus") {
                guard draftObservations.count < PersonaDefaults.maximumActiveObservations else { return }
                draftObservations.append(
                    PersonaRepository.makeObservation(
                        text: "", origin: .user, isUserProtected: true, evidenceSource: .user
                    ))
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .padding(16).background(RezplyColor.secondaryContainer.opacity(0.3), in: RoundedRectangle(cornerRadius: 18))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var exampleLines: [String] {
        examples.split(whereSeparator: \.isNewline).map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func selectBase(_ id: UUID?) {
        guard let id, let persona = personas.first(where: { $0.id == id }) else {
            draftObservations = []
            return
        }
        if summary.isEmpty { summary = persona.summary }
        if instructions.isEmpty { instructions = persona.instructions }
        draftObservations = storedObservations.filter {
            $0.personaID == id && $0.status == PersonaObservationStatus.active.rawValue
        }.map {
            PersonaRepository.makeObservation(
                text: $0.text, origin: .seed, isUserProtected: false, evidenceSource: .seed)
        }
    }

    private func advance() {
        if step == 1 { compileQuickStyle() }
        step += 1
    }

    private func compileQuickStyle() {
        let texts = PersonaQuickSetup.replacingQuickSetupObservations(
            in: draftObservations.map(\.text), selections: selections
        )
        let existing = Dictionary(uniqueKeysWithValues: draftObservations.map { ($0.text.lowercased(), $0) })
        draftObservations = texts.prefix(PersonaDefaults.maximumActiveObservations).map { text in
            existing[text.lowercased()]
                ?? PersonaRepository.makeObservation(
                    text: text, origin: .seed, isUserProtected: false, evidenceSource: .seed
                )
        }
    }

    private func analyzeExamples() {
        KeyboardDismissal.dismiss()
        isAnalyzing = true
        errorMessage = nil
        let context = PersonaPromptContext(
            id: UUID(), name: trimmedName, instructions: instructions,
            observations: draftObservations, protectedTombstones: []
        )
        Task {
            do {
                let result = try await PersonaExampleAnalyzer(providerStore: providerStore)
                    .analyze(persona: context, examples: exampleLines)
                apply(result.changes)
                examples = ""
            } catch { errorMessage = error.localizedDescription }
            isAnalyzing = false
        }
    }

    private func apply(_ changes: [PersonaObservationChange]) {
        for change in changes {
            switch change.action {
            case .add:
                guard let text = change.text, draftObservations.count < PersonaDefaults.maximumActiveObservations,
                    !draftObservations.contains(where: { $0.text.caseInsensitiveCompare(text) == .orderedSame })
                else { continue }
                draftObservations.append(
                    PersonaRepository.makeObservation(
                        text: text, origin: .ai, isUserProtected: false, evidenceSource: .examples,
                        evidenceCount: change.sourceMessageIDs.count
                    ))
            case .update:
                guard let id = change.targetObservationID, let text = change.text,
                    let index = draftObservations.firstIndex(where: { $0.id == id && !$0.isUserProtected })
                else { continue }
                draftObservations[index] = PersonaRepository.makeObservation(
                    text: text, origin: .ai, isUserProtected: false, evidenceSource: .examples,
                    evidenceCount: change.sourceMessageIDs.count
                )
            case .archive:
                guard let id = change.targetObservationID else { continue }
                draftObservations.removeAll { $0.id == id && !$0.isUserProtected }
            }
        }
    }

    private func create() {
        let clean = draftObservations.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let record = try? PersonaRepository().create(
            name: trimmedName, summary: summary, instructions: instructions, observations: clean
        ) {
            onCreated(record)
        }
    }
}

extension View {
    fileprivate func editorPanel() -> some View {
        scrollContentBackground(.hidden).padding(10)
            .background(RezplyColor.secondaryContainer.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
    }
}
