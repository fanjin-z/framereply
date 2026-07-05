import SwiftData
import SwiftUI

struct PersonaDetailView: View {
    let personaID: UUID
    @ObservedObject var providerStore: ProviderStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var personas: [PersonaRecord]
    @Query private var traits: [PersonaLearnedTraitRecord]
    @Query private var assignments: [ContactContextRecord]
    @State private var showsGuidance = false
    @State private var examples = ""
    @State private var editingTraitID: UUID?
    @State private var traitDraft = ""
    @State private var isAnalyzingExamples = false
    @State private var exampleError: String?

    init(personaID: UUID, providerStore: ProviderStore) {
        self.personaID = personaID
        self.providerStore = providerStore
        _personas = Query(filter: #Predicate<PersonaRecord> { $0.id == personaID })
        _traits = Query(
            filter: #Predicate<PersonaLearnedTraitRecord> { $0.personaID == personaID },
            sort: \PersonaLearnedTraitRecord.category
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
                        hero(persona)
                        controls(persona)
                        guidance(persona)
                        learnedStyle(persona)
                        exampleCard(persona)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .interactiveSwipeBackEnabled()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.68), in: Circle())
            }
            .buttonStyle(SoftPressButtonStyle())
            Spacer()
        }
        .foregroundStyle(RezplyColor.primary)
    }

    private func hero(_ persona: PersonaRecord) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Circle()
                .fill(persona.value.accent.opacity(0.14))
                .frame(width: 58, height: 58)
                .overlay(Image(systemName: persona.symbolName).font(.system(size: 24)).foregroundStyle(persona.value.accent))
            VStack(alignment: .leading, spacing: 8) {
                if persona.isBuiltIn {
                    Text(persona.name).font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(persona.summary)
                } else {
                    TextField("Name", text: binding(persona, \.name))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    TextField("What is this voice for?", text: binding(persona, \.summary), axis: .vertical)
                }
                Label(persona.isBuiltIn ? "Built-in · \(assignments.count) chats" : "Custom · \(assignments.count) chats", systemImage: "message")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RezplyColor.outline)
            }
            .foregroundStyle(RezplyColor.onSurface)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 28)
    }

    private func controls(_ persona: PersonaRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(symbolName: "slider.horizontal.3", title: "Style Controls")
            control("Formality", selection: binding(persona, \.formality), values: PersonaFormality.allCases.map(\.rawValue))
            control("Warmth", selection: binding(persona, \.warmth), values: PersonaWarmth.allCases.map(\.rawValue))
            control("Reply length", selection: binding(persona, \.replyLength), values: PersonaLength.allCases.map(\.rawValue))
            control("Emoji", selection: binding(persona, \.emojiUse), values: PersonaEmojiUse.allCases.map(\.rawValue))
        }
        .padding(22)
        .glassPanel(cornerRadius: 28)
    }

    private func control(_ title: String, selection: Binding<String>, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func guidance(_ persona: PersonaRecord) -> some View {
        DisclosureGroup(isExpanded: $showsGuidance) {
            TextEditor(text: binding(persona, \.additionalGuidance))
                .font(.system(size: 15, design: .rounded))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(10)
                .background(RezplyColor.secondaryContainer.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
                .padding(.top, 12)
        } label: {
            SectionHeader(symbolName: "text.quote", title: "Additional Guidance")
        }
        .padding(22)
        .glassPanel(cornerRadius: 28)
    }

    private func learnedStyle(_ persona: PersonaRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(symbolName: "sparkles", title: "Learned From Your Messages") {
                Toggle("", isOn: Binding(
                    get: { persona.learningEnabled },
                    set: { try? PersonaRepository().setLearningEnabled($0, for: persona) }
                )).labelsHidden()
            }
            Text(persona.sampleCount == 0 ? "No future messages analyzed yet." : "Learned from \(persona.sampleCount) messages.")
                .font(.system(size: 13, design: .rounded)).foregroundStyle(RezplyColor.outline)

            ForEach(traits.filter { $0.status == PersonaTraitStatus.active.rawValue }) { trait in
                traitRow(trait)
            }

            if !traits.isEmpty {
                Button("Reset Learned Style", role: .destructive) {
                    try? PersonaRepository().resetLearnedStyle(personaID: personaID)
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
            }
        }
        .padding(22)
        .glassPanel(cornerRadius: 28)
    }

    private func traitRow(_ trait: PersonaLearnedTraitRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(PersonaTraitCategory(rawValue: trait.category)?.displayName ?? trait.category)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Text(trait.confidence >= 0.8 ? "Established" : trait.confidence >= 0.55 ? "Growing" : "Emerging")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(RezplyColor.outline)
            }
            if editingTraitID == trait.id {
                TextField("Observation", text: $traitDraft, axis: .vertical)
                HStack {
                    Button("Remove", role: .destructive) { trait.status = PersonaTraitStatus.dismissed.rawValue; save() }
                    Spacer()
                    Button("Cancel") { editingTraitID = nil }
                    Button("Save") {
                        trait.observation = traitDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        trait.origin = PersonaTraitOrigin.userConfirmed.rawValue
                        trait.confidence = 1
                        editingTraitID = nil
                        save()
                    }.disabled(traitDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.font(.system(size: 12, weight: .bold, design: .rounded))
            } else {
                Button {
                    editingTraitID = trait.id; traitDraft = trait.observation
                } label: {
                    Text(trait.observation).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
        .font(.system(size: 14, design: .rounded))
        .foregroundStyle(RezplyColor.onSurface)
        .padding(14)
        .background(RezplyColor.secondaryContainer.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
    }

    private func exampleCard(_ persona: PersonaRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "quote.bubble", title: "Teach It Your Voice")
            Text("Optional: paste 3–10 messages you wrote, one per line. Examples are discarded after analysis.")
                .font(.system(size: 13, design: .rounded)).foregroundStyle(RezplyColor.outline)
            TextEditor(text: $examples)
                .font(.system(size: 15, design: .rounded)).scrollContentBackground(.hidden)
                .frame(minHeight: 120).padding(10)
                .background(RezplyColor.secondaryContainer.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
            if let exampleError {
                Text(exampleError).font(.system(size: 12, design: .rounded)).foregroundStyle(.red)
            }
            Button(isAnalyzingExamples ? "Analyzing…" : "Analyze Examples") {
                analyzeExamples()
            }
                .buttonStyle(SoftPressButtonStyle())
                .disabled(exampleLines.count < 3 || exampleLines.count > 10 || isAnalyzingExamples)
        }
        .padding(22)
        .glassPanel(cornerRadius: 28)
    }

    private var exampleLines: [String] {
        examples.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func analyzeExamples() {
        let lines = exampleLines
        guard (3...10).contains(lines.count) else { return }
        isAnalyzingExamples = true
        exampleError = nil
        Task {
            do {
                try await PersonaExampleAnalyzer(providerStore: providerStore).analyze(
                    personaID: personaID, examples: lines
                )
                examples = ""
            } catch {
                exampleError = error.localizedDescription
            }
            isAnalyzingExamples = false
        }
    }

    private func binding(_ record: PersonaRecord, _ keyPath: ReferenceWritableKeyPath<PersonaRecord, String>) -> Binding<String> {
        Binding(get: { record[keyPath: keyPath] }, set: { record[keyPath: keyPath] = $0; record.updatedAt = Date(); save() })
    }

    private func save() { try? modelContext.save() }
}
