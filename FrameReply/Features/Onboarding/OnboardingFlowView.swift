import SwiftData
import SwiftUI

struct OnboardingFlowView: View {
    private enum Step {
        case provider
        case persona
        case shortcuts
    }

    @ObservedObject var providerStore: ProviderStore
    private let chatRepository: ChatRepository
    private let personaRepository: PersonaRepository
    let presentation: OnboardingPresentation
    let onComplete: (AppTab) -> Void

    @Query(sort: \PersonaRecord.createdAt) private var personaRecords: [PersonaRecord]
    @State private var step: Step
    @State private var isConnectionInProgress = false
    @State private var isSkipSetupPresented = false
    @State private var isCreatePersonaPresented = false
    @State private var isShortcutHowToPresented = false
    @State private var confirmedPersonaID: UUID?
    @State private var defaultPersonaError: String?

    init(
        providerStore: ProviderStore,
        chatRepository: ChatRepository,
        personaRepository: PersonaRepository,
        presentation: OnboardingPresentation,
        onComplete: @escaping (AppTab) -> Void
    ) {
        self.providerStore = providerStore
        self.chatRepository = chatRepository
        self.personaRepository = personaRepository
        self.presentation = presentation
        self.onComplete = onComplete
        let initialStep: Step
        switch presentation {
        case .initial:
            initialStep = providerStore.providers.isEmpty ? .provider : .persona
        case .update, .none:
            initialStep = .shortcuts
        }
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()

                VStack(spacing: 0) {
                    onboardingTopBar

                    switch step {
                    case .provider:
                        ScrollView {
                            providerStep
                                .frame(maxWidth: 640)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                                .padding(.bottom, 36)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .scrollIndicators(.hidden)
                    case .persona:
                        ZStack(alignment: .bottom) {
                            ScrollView {
                                personaStep
                                    .frame(maxWidth: 640)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 24)
                                    .padding(.bottom, 174)
                            }
                            .scrollIndicators(.hidden)

                            VStack(spacing: 20) {
                                HStack {
                                    Spacer()
                                    floatingCreatePersonaButton
                                }
                                .padding(.horizontal, 20)
                                .frame(maxWidth: 640)
                                .frame(maxWidth: .infinity)

                                continueToShortcutsButton
                                    .frame(maxWidth: 640)
                                    .padding(.horizontal, 20)
                            }
                            .padding(.bottom, 28)
                        }
                    case .shortcuts:
                        VStack(spacing: 0) {
                            ScrollView {
                                shortcutsStep
                                    .frame(maxWidth: 640)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 24)
                            }
                            .scrollIndicators(.hidden)

                            finishSetupButton
                                .frame(maxWidth: 640)
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                .padding(.bottom, 28)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $isCreatePersonaPresented) {
                CreatePersonaView(
                    providerStore: providerStore,
                    chatRepository: chatRepository,
                    personaRepository: personaRepository,
                    onCreated: selectCreatedPersona
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert(
                "Skip setup?",
                isPresented: $isSkipSetupPresented,
            ) {
                Button("Skip Anyway", role: .destructive) {
                    onComplete(.settings)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You need a provider before you can generate replies.")
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
        .tint(FrameReplyColor.primary)
        .sheet(isPresented: $isShortcutHowToPresented) {
            ShortcutHowToView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var onboardingTopBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                progressDot(isActive: step == .provider)
                progressDot(isActive: step == .persona)
                progressDot(isActive: step == .shortcuts)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progressAccessibilityLabel)
            .accessibilityIdentifier("onboarding-screen")

            Spacer()

            if step == .provider {
                Button("Skip Setup") {
                    isSkipSetupPresented = true
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .disabled(isConnectionInProgress)
                .accessibilityIdentifier("continue-without-provider")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var progressAccessibilityLabel: LocalizedStringResource {
        switch step {
        case .provider: "Step 1 of 3"
        case .persona: "Step 2 of 3"
        case .shortcuts: "Step 3 of 3"
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect a Model Provider")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
                .accessibilityIdentifier("onboarding-provider-step")

            ProviderConnectionView(
                providerStore: providerStore,
                isConnectionInProgress: $isConnectionInProgress,
                title: nil,
                onConnected: advanceToPersona,
                onCancel: nil
            )
        }
    }

    private var personaStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Select Default Persona")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
                .accessibilityIdentifier("onboarding-persona-step")

            VStack(spacing: 16) {
                ForEach(personaRecords) { record in
                    PersonaCard(
                        persona: record.value,
                        usageCount: (try? personaRepository.usageCount(personaID: record.id)) ?? 0,
                        isDefault: confirmedPersonaID == record.id,
                        onTap: { selectPersona(record.id) },
                        onSetDefault: nil,
                        onDuplicate: nil,
                        onDelete: nil
                    )
                    .accessibilityIdentifier(personaCardIdentifier(record))
                }
            }
        }
    }

    private var floatingCreatePersonaButton: some View {
        CreatePersonaFloatingButton(accessibilityIdentifier: "onboarding-create-persona") {
            isCreatePersonaPresented = true
        }
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Shortcuts")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .accessibilityIdentifier("onboarding-shortcuts-step")
                Text("Import messages faster")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                Button {
                    isShortcutHowToPresented = true
                } label: {
                    Label("See How It Works", systemImage: "play.circle")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.primary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding-shortcut-how-to")
            }

            ShortcutSetupSection(showsHeader: false)
        }
    }

    private var continueToShortcutsButton: some View {
        Button(action: advanceToShortcuts) {
            Text("Continue")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background {
                    Capsule(style: .continuous)
                        .fill(FrameReplyColor.primary)
                        .opacity(confirmedPersonaID == nil ? 0.45 : 1)
                }
        }
        .buttonStyle(SoftPressButtonStyle())
        .disabled(confirmedPersonaID == nil)
        .accessibilityIdentifier("continue-from-persona")
    }

    private var finishSetupButton: some View {
        Button {
            onComplete(providerStore.providers.isEmpty ? .settings : .chats)
        } label: {
            Text("Finish Setup")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background {
                    Capsule(style: .continuous).fill(FrameReplyColor.primary)
                }
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityIdentifier("finish-onboarding")
    }

    private func progressDot(isActive: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(isActive ? FrameReplyColor.primary : FrameReplyColor.outlineVariant)
            .frame(width: isActive ? 24 : 8, height: 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.84), value: step)
    }

    private func personaCardIdentifier(_ record: PersonaRecord) -> String {
        if let builtInID = record.builtInID {
            return "onboarding-persona-card-\(builtInID.rawValue)"
        }
        return "onboarding-persona-card-\(record.id.uuidString.lowercased())"
    }

    private func selectPersona(_ personaID: UUID) {
        do {
            try personaRepository.setDefaultPersona(id: personaID)
            confirmedPersonaID = personaID
        } catch {
            defaultPersonaError = error.localizedDescription
        }
    }

    private func selectCreatedPersona(_ record: PersonaRecord) {
        do {
            try personaRepository.setDefaultPersona(id: record.id)
            confirmedPersonaID = record.id
        } catch {
            defaultPersonaError = error.localizedDescription
        }
        isCreatePersonaPresented = false
    }

    private func advanceToPersona() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            step = .persona
        }
    }

    private func advanceToShortcuts() {
        guard confirmedPersonaID != nil else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            step = .shortcuts
        }
    }
}
