import SwiftUI

struct ProviderConnectionView: View {
    @ObservedObject var providerStore: ProviderStore
    @Binding var isConnectionInProgress: Bool

    let title: LocalizedStringResource?
    let onConnected: () -> Void
    let onCancel: (() -> Void)?

    @State private var selectedPlatform: ProviderPlatform?
    @State private var selectedTier: ProviderTier?
    @State private var apiKey = ""
    @State private var status: AddProviderStatus = .idle
    @State private var providerAwaitingConsent: ProviderPlatform?
    @State private var providerDataDetails: ProviderPlatform?

    var body: some View {
        AddProviderCard(
            selectedPlatform: $selectedPlatform,
            selectedTier: $selectedTier,
            apiKey: $apiKey,
            status: $status,
            title: title,
            onConnect: requestProviderConnection,
            onShowDataSharingDetails: showProviderDataSharingDetails,
            onCancel: onCancel
        )
        .onChange(of: apiKey) { _, _ in
            if case .failed = status {
                status = .idle
            }
        }
        .onChange(of: selectedPlatform) { _, _ in
            if case .failed = status {
                status = .idle
            }
        }
        .onChange(of: selectedTier) { _, _ in
            if case .connected = status {
                status = .idle
            }
        }
        .alert(
            consentDisclosure?.permissionTitle ?? "Share chat content?",
            isPresented: Binding(
                get: { providerAwaitingConsent != nil },
                set: { if $0 == false { providerAwaitingConsent = nil } }
            )
        ) {
            Button("Not Now", role: .cancel) {
                providerAwaitingConsent = nil
            }
            .accessibilityIdentifier("provider-consent-cancel")
            Button("Allow & Connect") {
                authorizeAndConnectProvider()
            }
            .accessibilityIdentifier("provider-consent-allow")
        } message: {
            Text(consentDisclosure?.permissionMessage ?? "")
        }
        .sheet(item: $providerDataDetails) { platform in
            ProviderDataSharingDetailsView(platform: platform)
        }
    }

    private func requestProviderConnection() {
        KeyboardDismissal.dismiss()
        guard let selectedPlatform else {
            status = .failed(String(localized: "Select a provider before connecting."))
            return
        }

        guard selectedTier != nil else {
            status = .failed(String(localized: "Select a performance tier before connecting."))
            return
        }

        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            status = .failed(String(localized: "Enter an API key before connecting."))
            return
        }

        if providerStore.hasValidDataConsent(for: selectedPlatform) {
            connectProvider()
        } else {
            providerAwaitingConsent = selectedPlatform
        }
    }

    private func authorizeAndConnectProvider() {
        guard let platform = providerAwaitingConsent, platform == selectedPlatform else {
            providerAwaitingConsent = nil
            status = .failed(String(localized: "Select the provider again and retry."))
            return
        }

        providerStore.grantDataConsent(for: platform)
        providerAwaitingConsent = nil
        connectProvider()
    }

    private func connectProvider() {
        guard let selectedPlatform, let selectedTier else {
            status = .failed(String(localized: "Complete the provider settings and retry."))
            return
        }

        isConnectionInProgress = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            status = .testing
        }

        Task {
            do {
                try await providerStore.connect(
                    platform: selectedPlatform,
                    tier: selectedTier,
                    apiKey: apiKey
                )

                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    status = .connected
                    isConnectionInProgress = false
                }
                onConnected()
                resetForm()
            } catch let error as ProviderConnectionError {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isConnectionInProgress = false
                    status = .failed(error.localizedDescription)
                }
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isConnectionInProgress = false
                    status = .failed(
                        String(
                            localized:
                                "Could not test the provider. Check your network and try again."
                        )
                    )
                }
            }
        }
    }

    private func resetForm() {
        selectedPlatform = nil
        selectedTier = nil
        apiKey = ""
        providerAwaitingConsent = nil
        status = .idle
    }

    private var consentDisclosure: ProviderDataConsentDisclosure? {
        providerAwaitingConsent.map(ProviderDataConsentDisclosure.init(provider:))
    }

    private func showProviderDataSharingDetails() {
        if let selectedPlatform {
            providerDataDetails = selectedPlatform
        }
    }
}
