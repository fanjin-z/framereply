import SwiftData
import SwiftUI

struct CreatePersonaView: View {
    @ObservedObject var providerStore: ProviderStore
    let onCreated: (PersonaRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PersonaRecord.createdAt) private var personas: [PersonaRecord]
    @Query private var storedObservations: [PersonaObservationRecord]
    @State private var name = ""
    @State private var summary = ""
    @State private var instructions = ""
    @State private var basePersonaID: UUID?
    @State private var selections: [String: Int] = [:]
    @State private var draftObservations: [PersonaObservation] = []
    @State private var examples = ""
    @State private var isCreating = false
    @State private var analysisError: String?
    @State private var creationError: String?

    var body: some View {
        ZStack {
            EtherealBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    basicsSection
                    styleSection
                    instructionsSection
                    voiceSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { creationBar }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .interactiveSwipeBackEnabled()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        FrameReplyTopBar {
            HStack(spacing: 12) {
                FrameReplyTopBarBackButton(accessibilityLabel: "Back") {
                    KeyboardDismissal.dismiss()
                    dismiss()
                }

                Text("New Persona")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)

                Spacer()
            }
        }
    }

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(symbolName: "person.text.rectangle", title: "Basics")
            labeledField("Persona name", placeholder: "e.g. Work Mode", text: $name)
            labeledField(
                "Description",
                placeholder: "e.g. Concise, polished replies for work conversations.",
                text: $summary
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Start from").font(.subheadline.bold())
                Picker("Start from", selection: $basePersonaID) {
                    Text("Blank persona").tag(UUID?.none)
                    ForEach(personas) { persona in
                        Text(persona.name).tag(Optional(persona.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(fieldBackground)
                .onChange(of: basePersonaID) { _, value in selectBase(value) }
            }

        }
        .padding(22)
        .glassPanel(cornerRadius: 28)
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(symbolName: "slider.horizontal.3", title: "Style")
                Text("Fine-tune the voice.")
                    .font(.caption)
                    .foregroundStyle(FrameReplyColor.outline)
            }

            ForEach(Array(PersonaQuickSetup.dimensions.enumerated()), id: \.element.id) {
                index, dimension in
                styleControl(dimension)
                if index < PersonaQuickSetup.dimensions.count - 1 {
                    Divider().opacity(0.45)
                }
            }
        }
        .padding(22)
        .glassPanel(cornerRadius: 28)
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(symbolName: "text.badge.checkmark", title: "Instructions")
            Text("Tell this persona how to respond.")
                .font(.caption)
                .foregroundStyle(FrameReplyColor.outline)
            TextEditor(text: $instructions)
                .overlay(alignment: .topLeading) {
                    if instructions.isEmpty {
                        instructionPlaceholder
                    }
                }
                .frame(minHeight: 130)
                .personaEditorPanel()
        }
        .padding(22)
        .glassPanel(cornerRadius: 28)
    }

    private func styleControl(_ dimension: PersonaQuickSetupDimension) -> some View {
        let selection = selections[dimension.id] ?? 0
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(dimension.title).font(.headline)
                Spacer()
                Text(dimension.label(for: selection))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FrameReplyColor.primary)
            }
            Slider(value: sliderBinding(for: dimension), in: -2...2, step: 1)
                .tint(FrameReplyColor.primary)
                .accessibilityLabel(dimension.title)
                .accessibilityValue(dimension.label(for: selection))
            HStack {
                Text(dimension.lowAnchor)
                Spacer()
                Text(dimension.highAnchor)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(FrameReplyColor.outline)
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "quote.bubble", title: "Teach It Your Voice")
            Text("Optional: paste 3–10 messages you wrote, one per line.")
                .font(.caption)
                .foregroundStyle(FrameReplyColor.outline)

            TextEditor(text: $examples)
                .frame(minHeight: 150)
                .personaEditorPanel()

            Text("\(exampleLines.count)/10 messages")
                .font(.caption)
                .foregroundStyle(FrameReplyColor.outline)

            if let analysisError {
                errorLabel(analysisError)
            }
        }
        .padding(22)
        .glassPanel(cornerRadius: 28)
    }

    private var creationBar: some View {
        VStack(spacing: 10) {
            if let creationError { errorLabel(creationError) }
            Button {
                create()
            } label: {
                HStack(spacing: 8) {
                    if isCreating { ProgressView().tint(.white) }
                    Text(
                        isCreating
                            ? LocalizedStringResource("Creating…")
                            : LocalizedStringResource("Create Persona")
                    )
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Capsule().fill(FrameReplyColor.primary))
            }
            .buttonStyle(SoftPressButtonStyle())
            .disabled(trimmedName.isEmpty || isCreating || hasInvalidExampleCount)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.35) }
    }

    private var fieldBackground: some ShapeStyle {
        FrameReplyColor.secondaryContainer.opacity(0.28)
    }

    private var instructionPlaceholder: some View {
        Text(
            "Example: For networking messages, mention the shared context, make one clear request, and give the other person an easy way to decline."
        )
        .foregroundStyle(FrameReplyColor.outline.opacity(0.7))
        .padding(.top, 8)
        .padding(.leading, 5)
        .allowsHitTesting(false)
    }

    private func labeledField(_ label: String, placeholder: String, text: Binding<String>)
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.bold())
            TextField(placeholder, text: text, axis: .vertical)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sliderBinding(for dimension: PersonaQuickSetupDimension) -> Binding<Double> {
        Binding(
            get: { Double(selections[dimension.id] ?? 0) },
            set: { selections[dimension.id] = Int($0.rounded()) }
        )
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var exampleLines: [String] {
        examples.split(whereSeparator: \.isNewline).map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var hasInvalidExampleCount: Bool {
        !exampleLines.isEmpty && !(3...10).contains(exampleLines.count)
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
            $0.value
        }
    }

    private func observationsIncludingStyle() -> [PersonaObservation] {
        Array(
            PersonaQuickSetup.replacingQuickSetupObservations(
                in: draftObservations,
                selections: selections
            ).prefix(PersonaLimits.maximumActiveObservations)
        )
    }

    private func analyzeExamplesForCreation() async throws {
        analysisError = nil
        let preparedObservations = observationsIncludingStyle()
        let context = PersonaPromptContext(
            id: UUID(), name: trimmedName, instructions: instructions,
            observations: preparedObservations, protectedTombstones: []
        )
        let result = try await PersonaExampleAnalyzer(providerStore: providerStore)
            .analyze(persona: context, examples: exampleLines)
        draftObservations = preparedObservations
        apply(result.changes)
        examples = ""
    }

    private func apply(_ changes: [PersonaObservationChange]) {
        for change in changes {
            switch change.action {
            case .add:
                guard let text = change.text,
                    draftObservations.count < PersonaLimits.maximumActiveObservations,
                    !draftObservations.contains(where: {
                        $0.text.caseInsensitiveCompare(text) == .orderedSame
                    })
                else { continue }
                draftObservations.append(
                    PersonaRepository.makeObservation(
                        text: text, origin: .ai, isUserProtected: false
                    )
                )
            case .update:
                guard let id = change.targetObservationID, let text = change.text,
                    let index = draftObservations.firstIndex(where: {
                        $0.id == id && !$0.isUserProtected
                    })
                else { continue }
                draftObservations[index] = PersonaRepository.makeObservation(
                    text: text, origin: .ai, isUserProtected: false
                )
            case .archive:
                guard let id = change.targetObservationID else { continue }
                draftObservations.removeAll { $0.id == id && !$0.isUserProtected }
            }
        }
    }

    private func create() {
        KeyboardDismissal.dismiss()
        isCreating = true
        creationError = nil
        Task {
            if !exampleLines.isEmpty {
                do {
                    try await analyzeExamplesForCreation()
                } catch {
                    analysisError = error.localizedDescription
                    isCreating = false
                    return
                }
            }
            do {
                let clean = observationsIncludingStyle().filter {
                    !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                let record = try PersonaRepository().create(
                    name: trimmedName, summary: summary, instructions: instructions,
                    observations: clean
                )
                onCreated(record)
            } catch {
                creationError = error.localizedDescription
                isCreating = false
            }
        }
    }
}

extension View {
    fileprivate func personaEditorPanel() -> some View {
        scrollContentBackground(.hidden)
            .padding(10)
            .background(
                FrameReplyColor.secondaryContainer.opacity(0.28),
                in: RoundedRectangle(cornerRadius: 18)
            )
    }
}
