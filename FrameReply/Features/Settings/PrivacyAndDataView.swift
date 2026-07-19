import SwiftData
import SwiftUI

struct PrivacyAndDataView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var providerStore: ProviderStore

    @State private var providerAwaitingConsent: ProviderPlatform?
    @State private var providerDataDetails: ProviderPlatform?
    @State private var isDeleteAllConfirmationPresented = false
    @State private var deleteAllError: String?

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    localDataSection
                    providerPermissionsSection
                    legalSection
                    deletionSection
                }
                .padding(24)
                .padding(.bottom, 24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
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
            Button("Allow") {
                if let platform = providerAwaitingConsent {
                    providerStore.grantDataConsent(for: platform)
                }
                providerAwaitingConsent = nil
            }
        } message: {
            Text(consentDisclosure?.permissionMessage ?? "")
        }
        .confirmationDialog(
            "Delete all local FrameReply data?",
            isPresented: $isDeleteAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete All Local Data", role: .destructive, action: deleteAllLocalData)
        } message: {
            Text(
                "This permanently deletes chats, messages, personas, drafts, provider settings, consent records, and API keys from this device."
            )
        }
        .alert(
            "Couldn’t Delete All Data",
            isPresented: Binding(
                get: { deleteAllError != nil },
                set: { if $0 == false { deleteAllError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteAllError ?? "")
        }
        .sheet(item: $providerDataDetails) { platform in
            ProviderDataSharingDetailsView(platform: platform)
        }
    }

    private var localDataSection: some View {
        settingsPanel(title: "On This Device", symbol: "iphone") {
            Text(
                "Chats, personas, and generated replies are stored locally. FrameReply has no proxy server, analytics, advertising, or tracking."
            )
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var providerPermissionsSection: some View {
        settingsPanel(title: "Provider Sharing", symbol: "network") {
            if displayedPlatforms.isEmpty {
                Text("No provider permissions have been granted.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            } else {
                ForEach(displayedPlatforms) { platform in
                    providerPermissionRow(platform)
                }
            }
        }
    }

    private var legalSection: some View {
        settingsPanel(title: "Policies & Support", symbol: "doc.text") {
            VStack(alignment: .leading, spacing: 12) {
                legalLink("Privacy Policy", destination: AppLegalLinks.privacy)
                    .accessibilityIdentifier("privacy-policy-link")
                legalLink("Terms of Use", destination: AppLegalLinks.terms)
                    .accessibilityIdentifier("terms-link")
                legalLink("Support", destination: AppLegalLinks.support)
                    .accessibilityIdentifier("support-link")
                legalLink("Age Suitability", destination: AppLegalLinks.ageSuitability)
                    .accessibilityIdentifier("age-suitability-link")
            }
        }
    }

    private var deletionSection: some View {
        settingsPanel(title: "Local Data", symbol: "externaldrive") {
            Button("Delete All Local Data", role: .destructive) {
                isDeleteAllConfirmationPresented = true
            }
            .accessibilityIdentifier("delete-all-local-data")
            .font(.system(size: 14, weight: .bold, design: .rounded))
        }
    }

    private var displayedPlatforms: [ProviderPlatform] {
        ProviderPlatform.availableCases.filter { platform in
            providerStore.providers.contains { $0.platform == platform }
                || providerStore.hasValidDataConsent(for: platform)
        }
    }

    private var consentDisclosure: ProviderDataConsentDisclosure? {
        providerAwaitingConsent.map { ProviderDataConsentDisclosure(provider: $0) }
    }

    private func providerPermissionRow(_ platform: ProviderPlatform) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                providerDataDetails = platform
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurface)
                    Text(
                        providerStore.hasValidDataConsent(for: platform)
                            ? "Sharing allowed" : "Sharing not allowed"
                    )
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(FrameReplyColor.outline)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if providerStore.hasValidDataConsent(for: platform) {
                Button("Stop Sharing", role: .destructive) {
                    providerStore.revokeDataConsent(for: platform)
                }
            } else {
                Button("Review & Allow") {
                    providerAwaitingConsent = platform
                }
            }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .padding(.vertical, 4)
    }

    private func legalLink(_ title: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
    }

    private func settingsPanel<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.primary)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.42))
    }

    private func deleteAllLocalData() {
        do {
            try providerStore.deleteAllProviderData()
            try FrameReplyDataStore.deleteAllUserData(in: modelContext)
            try ChatRepository(context: modelContext).seedIfNeeded()
            try PersonaRepository(context: modelContext).seedPersonasIfNeeded()
        } catch {
            deleteAllError =
                "Some local data could not be deleted. Restart FrameReply and try again before sharing the device."
        }
    }
}
