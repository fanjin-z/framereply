import SwiftData
import SwiftUI

struct PersonaDetailView: View {
    let personaID: UUID
    @ObservedObject var providerStore: ProviderStore
    private let chatRepository: ChatRepository
    private let personaRepository: PersonaRepository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var personas: [PersonaRecord]
    @Query private var observations: [PersonaObservationRecord]
    @Query private var assignments: [ChatContextRecord]
    @State private var examples = ""
    @State private var newObservation = ""
    @State private var editingID: UUID?
    @State private var observationDraft = ""
    @State private var revealedObservationID: UUID?
    @State private var isAnalyzing = false
    @State private var exampleError: String?
    @State private var defaultPersonaID: UUID?
    @State private var showsHistory = false

    init(
        personaID: UUID,
        providerStore: ProviderStore,
        chatRepository: ChatRepository,
        personaRepository: PersonaRepository
    ) {
        self.personaID = personaID
        self.providerStore = providerStore
        self.chatRepository = chatRepository
        self.personaRepository = personaRepository
        _personas = Query(filter: #Predicate<PersonaRecord> { $0.id == personaID })
        _observations = Query(
            filter: #Predicate<PersonaObservationRecord> { $0.personaID == personaID },
            sort: \PersonaObservationRecord.createdAt
        )
        _assignments = Query(filter: #Predicate<ChatContextRecord> { $0.personaID == personaID })
    }

    var body: some View {
        ZStack {
            EtherealBackground()
            if let persona = personas.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        identity(persona)
                        instructionsCard(persona)
                        observationsCard(persona)
                        exampleCard
                        historyCard
                    }
                    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 40)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("persona-detail-screen")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .task { defaultPersonaID = try? personaRepository.defaultPersonaID() }
        .interactiveSwipeBackEnabled().navigationBarBackButtonHidden(true).toolbar(
            .hidden, for: .navigationBar)
    }

    private var topBar: some View {
        FrameReplyTopBar {
            HStack(spacing: 12) {
                FrameReplyTopBarBackButton(accessibilityLabel: "Back") {
                    KeyboardDismissal.dismiss()
                    dismiss()
                }

                Spacer()

                if defaultPersonaID == personaID {
                    Label("Default", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                } else {
                    Button("Set as Default") {
                        try? personaRepository.setDefaultPersona(id: personaID)
                        defaultPersonaID = personaID
                    }
                    .font(.caption.bold())
                }
            }
            .foregroundStyle(FrameReplyColor.primary)
        }
    }

    private func identity(_ persona: PersonaRecord) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Circle().fill(persona.value.accent.opacity(0.14)).frame(width: 58, height: 58)
                .overlay(
                    Image(systemName: persona.symbolName).font(.system(size: 24)).foregroundStyle(
                        persona.value.accent))
            VStack(alignment: .leading, spacing: 8) {
                TextField("e.g. Work Mode", text: binding(persona, \.name))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                TextField(
                    "e.g. Concise, polished replies for work conversations.",
                    text: binding(persona, \.summary), axis: .vertical
                )
                Label("\(assignments.count) chats", systemImage: "message")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(
                        FrameReplyColor.outline)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).glassPanel(cornerRadius: 28)
    }

    private func instructionsCard(_ persona: PersonaRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(symbolName: "text.badge.checkmark", title: "Instructions")
            Text("Tell this persona how to respond.")
                .font(.caption).foregroundStyle(FrameReplyColor.outline)
            TextEditor(text: binding(persona, \.instructions))
                .overlay(alignment: .topLeading) {
                    if persona.instructions.isEmpty {
                        Text(
                            "Example: For networking messages, mention the shared context, make one clear request, and give the other person an easy way to decline."
                        )
                        .foregroundStyle(FrameReplyColor.outline.opacity(0.7))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 130)
                .scrollContentBackground(.hidden).padding(10)
                .background(
                    FrameReplyColor.secondaryContainer.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 18))
        }.padding(22).glassPanel(cornerRadius: 28)
    }

    private func observationsCard(_ persona: PersonaRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "sparkles", title: "Observations") {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { persona.learningEnabled },
                        set: { try? personaRepository.setLearningEnabled($0, for: persona) }
                    )
                ).labelsHidden()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("persona-observations-card")
            .padding(.horizontal, 22)
            .padding(.top, 22)

            if !activeObservations.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(activeObservations.enumerated()), id: \.element.id) {
                        index, observation in
                        observationRow(
                            observation,
                            showsSeparator: index < activeObservations.count - 1
                        )
                    }
                }
                .background(FrameReplyColor.surfaceContainerLow)
                .clipped()
            }

            HStack {
                TextField("Add an observation", text: $newObservation, axis: .vertical)
                Button("Add") {
                    KeyboardDismissal.dismiss()
                    try? personaRepository.addUserObservation(
                        newObservation, personaID: personaID)
                    newObservation = ""
                }.disabled(
                    newObservation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || activeObservations.count >= PersonaLimits.maximumActiveObservations)
            }
            .padding(14)
            .background(
                FrameReplyColor.secondaryContainer.opacity(0.2),
                in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 22)
            .padding(.bottom, 22)

        }
        .glassPanel(cornerRadius: 28)
    }

    @ViewBuilder
    private func observationRow(
        _ observation: PersonaObservationRecord,
        showsSeparator: Bool
    ) -> some View {
        if editingID == observation.id {
            VStack(alignment: .leading, spacing: 10) {
                observationMetadata(observation)

                TextField("Observation", text: $observationDraft, axis: .vertical)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .accessibilityIdentifier(
                        "persona-observation-editor-\(observation.id.uuidString)"
                    )

                HStack(spacing: 12) {
                    Button("Remove", role: .destructive) { archive(observation) }
                        .frame(minWidth: 72, minHeight: 44)
                    Spacer()
                    Button("Cancel") { editingID = nil }
                        .frame(minWidth: 72, minHeight: 44)
                    Button("Save") {
                        KeyboardDismissal.dismiss()
                        try? personaRepository.updateObservation(
                            observation, text: observationDraft)
                        editingID = nil
                    }.disabled(
                        observationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(minWidth: 72, minHeight: 44)
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .compactSwipeRowSurface(showsSeparator: showsSeparator)
        } else {
            CompactSwipeRow(
                isRevealed: revealedObservationID == observation.id,
                onReveal: {
                    editingID = nil
                    revealedObservationID = observation.id
                },
                onClose: {
                    if revealedObservationID == observation.id {
                        revealedObservationID = nil
                    }
                },
                onAction: {
                    archive(observation)
                },
                actionTitle: "Remove",
                actionSystemImage: "trash",
                actionTint: .red,
                actionAccessibilityIdentifier:
                    "persona-observation-remove-\(observation.id.uuidString)"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    observationMetadata(observation)

                    Text(verbatim: observation.localizedText)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurface)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    if revealedObservationID == observation.id {
                        revealedObservationID = nil
                    } else {
                        beginEditing(observation)
                    }
                }
                .compactSwipeRowSurface(showsSeparator: showsSeparator)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Observation: \(observation.localizedText)")
                .accessibilityHint("Double tap to edit, or swipe left to remove")
                .accessibilityIdentifier(
                    "persona-observation-row-\(observation.id.uuidString)"
                )
                .accessibilityAction(named: "Edit") {
                    beginEditing(observation)
                }
                .accessibilityAction(named: "Remove") {
                    archive(observation)
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") {
                        beginEditing(observation)
                    }
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        archive(observation)
                    }
                }
            }
        }
    }

    private func observationMetadata(_ observation: PersonaObservationRecord) -> some View {
        HStack {
            Label(
                sourceLabel(observation),
                systemImage: observation.isUserProtected ? "lock.fill" : "sparkles"
            )
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(FrameReplyColor.outline)

            Spacer()

            Text(observation.updatedAt, style: .date)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(FrameReplyColor.outline)
        }
    }

    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(symbolName: "quote.bubble", title: "Teach It Your Voice")
            Text("Paste 3–10 messages you wrote, one per line.")
                .font(.caption).foregroundStyle(FrameReplyColor.outline)
            TextEditor(text: $examples).frame(minHeight: 120).scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    FrameReplyColor.secondaryContainer.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 18))
            if let exampleError { Text(exampleError).font(.caption).foregroundStyle(.red) }
            Button(
                isAnalyzing
                    ? LocalizedStringResource("Analyzing…")
                    : LocalizedStringResource("Analyze Examples")
            ) { analyzeExamples() }
            .buttonStyle(SoftPressButtonStyle())
            .disabled(!(3...10).contains(exampleLines.count) || isAnalyzing)
        }.padding(22).glassPanel(cornerRadius: 28)
    }

    private var historyCard: some View {
        DisclosureGroup(isExpanded: $showsHistory) {
            if inactiveObservations.isEmpty {
                Text("No archived observations.").font(.caption).foregroundStyle(
                    FrameReplyColor.outline
                ).padding(.top, 8)
            } else {
                ForEach(inactiveObservations) { observation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: observation.localizedText)
                        Text(observation.status.capitalized).font(.caption2).foregroundStyle(
                            FrameReplyColor.outline)
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

    private func beginEditing(_ observation: PersonaObservationRecord) {
        revealedObservationID = nil
        editingID = observation.id
        observationDraft = observation.localizedText
    }

    private func archive(_ observation: PersonaObservationRecord) {
        revealedObservationID = nil
        try? personaRepository.archiveObservation(observation)
        editingID = nil
    }

    private func analyzeExamples() {
        KeyboardDismissal.dismiss()
        isAnalyzing = true
        exampleError = nil
        Task {
            do {
                try await PersonaExampleAnalyzer(
                    providerStore: providerStore,
                    repository: chatRepository
                ).analyze(
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
