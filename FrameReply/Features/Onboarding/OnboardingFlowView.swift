import SwiftUI

struct OnboardingFlowView: View {
    private enum Step {
        case provider
        case shortcuts
    }

    @ObservedObject var providerStore: ProviderStore
    let presentation: OnboardingPresentation
    let onComplete: (AppTab) -> Void

    @State private var step: Step
    @State private var isConnectionInProgress = false
    @State private var isSkipSetupPresented = false

    init(
        providerStore: ProviderStore,
        presentation: OnboardingPresentation,
        onComplete: @escaping (AppTab) -> Void
    ) {
        self.providerStore = providerStore
        self.presentation = presentation
        self.onComplete = onComplete
        let initialStep: Step
        switch presentation {
        case .initial:
            initialStep = providerStore.providers.isEmpty ? .provider : .shortcuts
        case .update, .none:
            initialStep = .shortcuts
        }
        _step = State(initialValue: initialStep)
    }

    var body: some View {
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
        .tint(FrameReplyColor.primary)
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
        .accessibilityIdentifier("onboarding-screen")
    }

    private var onboardingTopBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                progressDot(isActive: step == .provider)
                progressDot(isActive: step == .shortcuts)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(step == .provider ? "Step 1 of 2" : "Step 2 of 2")

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

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect a Model Provider")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)

            ProviderConnectionView(
                providerStore: providerStore,
                isConnectionInProgress: $isConnectionInProgress,
                title: nil,
                onConnected: advanceToShortcuts,
                onCancel: nil
            )
        }
        .accessibilityIdentifier("onboarding-provider-step")
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Shortcuts")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                Text("Import messages faster")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }

            ShortcutSetupSection(showsHeader: false)
        }
        .accessibilityIdentifier("onboarding-shortcuts-step")
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

    private func advanceToShortcuts() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            step = .shortcuts
        }
    }
}
