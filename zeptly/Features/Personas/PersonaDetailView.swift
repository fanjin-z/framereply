import SwiftData
import SwiftUI

struct PersonaDetailView: View {
    let personaID: UUID
    @ObservedObject var providerStore: ProviderStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var personas: [PersonaRecord]
    @Query private var observations: [PersonaObservationRecord]
    @Query private var assignments: [ContactContextRecord]
    @State private var examples = ""
    @State private var newObservation = ""
    @State private var editingID: UUID?
    @State private var observationDraft = ""
    @State private var isAnalyzing = false
    @State private var exampleError: String?
    @State private var defaultPersonaID: UUID?
    @State private var showsHistory = false

    init(personaID: UUID, providerStore: ProviderStore) {
        self.personaID = personaID
        self.providerStore = providerStore
        _personas = Query(filter: #Predicate<PersonaRecord> { $0.id == personaID })
        _observations = Query(
            filter: #Predicate<PersonaObservationRecord> { $0.personaID == personaID },
            sort: \PersonaObservationRecord.createdAt
        )
        _assignments = Query(filter: #Predicate<ContactContextRecord> { $0.personaID == personaID })
    }

    var body: some View {
        ZStack {
            EtherealBackground()
            if let persona = personas.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        topBar
                        identity(persona)
                        instructionsCard(persona)
                        observationsCard(persona)
                        exampleCard
                        historyCard
                    }
                    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 40)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                }.scrollIndicators(.hidden)
            }
        }
        .task { defaultPersonaID = try? PersonaRepository().defaultPersonaID() }
        .interactiveSwipeBackEnabled().navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            Button {
                KeyboardDismissal.dismiss()
                dismiss()
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                    .frame(width: 46, height: 46).background(Color.white.opacity(0.68), in: Circle())
            }.buttonStyle(SoftPressButtonStyle())
            Spacer()
            if defaultPersonaID == personaID {
                Label("Default", systemImage: "checkmark.circle.fill").font(.caption.bold())
            } else {
                Button("Set as Default") {
                    try? PersonaRepository().setDefaultPersona(id: personaID)
                    defaultPersonaID = personaID
                }.font(.caption.bold())
            }
        }.foregroundStyle(RezplyColor.primary)
    }

    private func identity(_ persona: PersonaRecord) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Circle().fill(persona.value.accent.opacity(0.14)).frame(width: 58, height: 58)
                .overlay(
                    Image(systemName: persona.symbolName).font(.system(size: 24)).foregroundStyle(persona.value.accent))
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: binding(persona, \.name))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                TextField("Short summary", text: binding(persona, \.summary), axis: .vertical)
                Label("\(assignments.count) chats", systemImage: "message")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(RezplyColor.outline)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).glassPanel(cornerRadius: 28)
    }

    private func instructionsCard(_ persona: PersonaRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(symbolName: "text.badge.checkmark", title: "Instructions")
            Text("Direct guidance always takes priority over learned observations.")
                .font(.caption).foregroundStyle(RezplyColor.outline)
            TextEditor(text: binding(persona, \.instructions)).frame(minHeight: 130)
                .scrollContentBackground(.hidden).padding(10)
                .background(RezplyColor.secondaryContainer.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
        }.padding(22).glassPanel(cornerRadius: 28)
    }

    private func observationsCard(_ persona: PersonaRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "sparkles", title: "Observations") {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { persona.learningEnabled },
                        set: { try? PersonaRepository().setLearningEnabled($0, for: persona) }
                    )
                ).labelsHidden()
            }
            Text(
                persona.sampleCount == 0
                    ? "Automatic learning has not analyzed messages yet."
                    : "Learned from \(persona.sampleCount) messages."
            )
            .font(.caption).foregroundStyle(RezplyColor.outline)

            ForEach(activeObservations) { observationRow($0) }

            HStack {
                TextField("Add an observation", text: $newObservation, axis: .vertical)
                Button("Add") {
                    KeyboardDismissal.dismiss()
                    try? PersonaRepository().addUserObservation(newObservation, personaID: personaID)
                    newObservation = ""
                }.disabled(
                    newObservation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || activeObservations.count >= PersonaDefaults.maximumActiveObservations)
            }.padding(14).background(
                RezplyColor.secondaryContainer.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))

            if activeObservations.contains(where: { $0.origin == PersonaObservationOrigin.ai.rawValue }) {
                Button("Clear Learned Observations", role: .destructive) {
                    try? PersonaRepository().clearLearnedObservations(personaID: personaID)
                }.font(.caption.bold())
            }
        }.padding(22).glassPanel(cornerRadius: 28)
    }

    private func observationRow(_ observation: PersonaObservationRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(sourceLabel(observation), systemImage: observation.isUserProtected ? "lock.fill" : "sparkles")
                    .font(.caption.bold()).foregroundStyle(RezplyColor.outline)
                Spacer()
                Text(observation.updatedAt, style: .date).font(.caption2).foregroundStyle(RezplyColor.outline)
            }
            if editingID == observation.id {
                TextField("Observation", text: $observationDraft, axis: .vertical)
                HStack {
                    Button("Remove", role: .destructive) { archive(observation) }
                    Spacer()
                    Button("Cancel") { editingID = nil }
                    Button("Save") {
                        KeyboardDismissal.dismiss()
                        try? PersonaRepository().updateObservation(observation, text: observationDraft)
                        editingID = nil
                    }.disabled(observationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.font(.caption.bold())
            } else {
                Button {
                    editingID = observation.id
                    observationDraft = observation.text
                } label: {
                    Text(observation.text).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }.padding(14).background(RezplyColor.secondaryContainer.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
    }

    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "quote.bubble", title: "Teach It Your Voice")
            Text("Paste 3–10 messages you wrote, one per line. Examples are discarded after analysis.")
                .font(.caption).foregroundStyle(RezplyColor.outline)
            TextEditor(text: $examples).frame(minHeight: 120).scrollContentBackground(.hidden).padding(10)
                .background(RezplyColor.secondaryContainer.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
            if let exampleError { Text(exampleError).font(.caption).foregroundStyle(.red) }
            Button(isAnalyzing ? "Analyzing…" : "Analyze Examples") { analyzeExamples() }
                .buttonStyle(SoftPressButtonStyle())
                .disabled(!(3...10).contains(exampleLines.count) || isAnalyzing)
        }.padding(22).glassPanel(cornerRadius: 28)
    }

    private var historyCard: some View {
        DisclosureGroup(isExpanded: $showsHistory) {
            if inactiveObservations.isEmpty {
                Text("No archived observations.").font(.caption).foregroundStyle(RezplyColor.outline).padding(.top, 8)
            } else {
                ForEach(inactiveObservations) { observation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(observation.text)
                        Text(observation.status.capitalized).font(.caption2).foregroundStyle(RezplyColor.outline)
                    }.padding(.top, 10)
                }
            }
        } label: {
            SectionHeader(symbolName: "clock.arrow.circlepath", title: "Observation History")
        }
        .padding(22).glassPanel(cornerRadius: 28)
    }

    private var activeObservations: [PersonaObservationRecord] {
        observations.filter { $0.status == PersonaObservationStatus.active.rawValue }
    }
    private var inactiveObservations: [PersonaObservationRecord] {
        observations.filter { $0.status != PersonaObservationStatus.active.rawValue }
    }
    private var exampleLines: [String] {
        examples.split(whereSeparator: \.isNewline).map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func sourceLabel(_ observation: PersonaObservationRecord) -> String {
        if observation.isUserProtected { return "Your guidance" }
        switch PersonaObservationOrigin(rawValue: observation.origin) {
        case .seed: return "Seed"
        case .ai: return "Learned"
        case .user: return "Your guidance"
        case nil: return "Observation"
        }
    }

    private func archive(_ observation: PersonaObservationRecord) {
        try? PersonaRepository().archiveObservation(observation)
        editingID = nil
    }

    private func analyzeExamples() {
        KeyboardDismissal.dismiss()
        isAnalyzing = true
        exampleError = nil
        Task {
            do {
                try await PersonaExampleAnalyzer(providerStore: providerStore).analyze(
                    personaID: personaID, examples: exampleLines
                )
                examples = ""
            } catch { exampleError = error.localizedDescription }
            isAnalyzing = false
        }
    }

    private func binding(
        _ record: PersonaRecord,
        _ keyPath: ReferenceWritableKeyPath<PersonaRecord, String>
    ) -> Binding<String> {
        Binding(
            get: { record[keyPath: keyPath] },
            set: {
                record[keyPath: keyPath] = $0
                record.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }
}
