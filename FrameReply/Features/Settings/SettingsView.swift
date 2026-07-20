//
//  SettingsView.swift
//  FrameReply
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var providerStore: ProviderStore
    let isActive: Bool
    let onShortcutGuideTap: () -> Void
    let onPrivacyAndDataTap: () -> Void

    @State private var selectedPlatform: ProviderPlatform?
    @State private var selectedTier: ProviderTier?
    @State private var apiKey = ""
    @State private var addProviderStatus: AddProviderStatus = .idle
    @State private var isAddProviderPresented = false
    @State private var isKeyboardPresented = false
    @State private var providerToRemove: ProviderConnection?
    @State private var providerRemovalError: String?
    @State private var providerAwaitingConsent: ProviderPlatform?
    @State private var providerDataDetails: ProviderPlatform?

    var body: some View {
        ZStack {
            providerList

            if isAddProviderPresented {
                addProviderPopup
            }
        }
        .onChange(of: apiKey) { _, _ in
            if case .failed = addProviderStatus {
                addProviderStatus = .idle
            }
        }
        .onChange(of: selectedPlatform) { _, _ in
            if case .failed = addProviderStatus {
                addProviderStatus = .idle
            }
        }
        .onChange(of: selectedTier) { _, _ in
            if case .connected = addProviderStatus {
                addProviderStatus = .idle
            }
        }
        .onChange(of: isActive) { _, isActive in
            if isActive == false {
                dismissAddProviderForTabChange()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                isKeyboardPresented = true
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                isKeyboardPresented = false
            }
        }
        .confirmationDialog(
            removeProviderTitle,
            isPresented: Binding(
                get: { providerToRemove != nil },
                set: { if $0 == false { providerToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                removeSelectedProvider()
            }
        } message: {
            Text(removeProviderMessage)
        }
        .alert(
            "Couldn’t Remove Provider",
            isPresented: Binding(
                get: { providerRemovalError != nil },
                set: { if $0 == false { providerRemovalError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(providerRemovalError ?? "")
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

    private var providerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    providerHeader
                    providerContent
                }

                shortcutSection
                privacyAndDataSection
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 94)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var providerHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 20, weight: .medium))
                Text("Model Providers")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
            }

            Spacer()

            Button {
                presentAddProvider()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(FrameReplyColor.primary)
                    }
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Add model provider")
            .accessibilityIdentifier("add-provider-header")
        }
        .foregroundStyle(FrameReplyColor.primary)
        .padding(.top, 16)
    }

    private var providerContent: some View {
        VStack(spacing: 18) {
            if providerStore.providers.isEmpty {
                Button {
                    presentAddProvider()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(FrameReplyColor.primary)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Add model provider")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurface)

                            Text("Connect OpenAI or a supported vision provider.")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.white.opacity(0.42))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("add-provider")
            } else {
                ForEach(providerStore.providers) { provider in
                    ProviderCard(
                        provider: provider,
                        isActive: providerStore.activePlatform == provider.platform,
                        onActivate: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                providerStore.activate(platform: provider.platform)
                            }
                        },
                        onTierChange: { tier in
                            providerStore.setTier(tier, for: provider.platform)
                        },
                        onRemove: {
                            providerToRemove = provider
                        }
                    )
                }
            }
        }
    }

    private var shortcutSection: some View {
        Group {
            if shouldShowShortcutSection {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Shortcuts", systemImage: "bolt.fill")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.primary)

                    shortcutInstallRow(
                        title: "Image Shortcut",
                        subtitle: "Import screenshots",
                        symbol: "photo.on.rectangle.angled",
                        installation: ShortcutInstallationCatalog.images
                    )
                    shortcutInstallRow(
                        title: "Text Shortcut",
                        subtitle: "Import copied messages",
                        symbol: "text.bubble",
                        installation: ShortcutInstallationCatalog.text
                    )

                    Button(action: onShortcutGuideTap) {
                        settingsNavigationLabel(
                            title: "Setup Guide",
                            subtitle: "Ways to run and troubleshoot Shortcuts",
                            symbol: "questionmark.circle"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shortcut-setup-guide")
                }
            }
        }
    }

    @ViewBuilder
    private func shortcutInstallRow(
        title: String,
        subtitle: String,
        symbol: String,
        installation: ShortcutInstallationDefinition
    ) -> some View {
        if let installationURL = installation.installationURL {
            compactShortcutRow(
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                trailing: AnyView(
                    Link("Install", destination: installationURL)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .accessibilityLabel("Install \(installation.title)")
                )
            )
        } else {
            #if DEBUG
                compactShortcutRow(
                    title: title,
                    subtitle: subtitle,
                    symbol: symbol,
                    trailing: AnyView(
                        Text("Unavailable")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(FrameReplyColor.outline)
                    )
                )
            #endif
        }
    }

    private func compactShortcutRow(
        title: String,
        subtitle: String,
        symbol: String,
        trailing: AnyView
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FrameReplyColor.primary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }

            Spacer()
            trailing
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 62)
        .background(Color.white.opacity(0.42))
    }

    private var shouldShowShortcutSection: Bool {
        #if DEBUG
            true
        #else
            ShortcutInstallationCatalog.all.contains { $0.installationURL != nil }
        #endif
    }

    private var addProviderPopup: some View {
        ZStack(alignment: isKeyboardPresented ? .top : .center) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissAddProvider()
                }

            AddProviderCard(
                selectedPlatform: $selectedPlatform,
                selectedTier: $selectedTier,
                apiKey: $apiKey,
                status: $addProviderStatus,
                onConnect: requestProviderConnection,
                onShowDataSharingDetails: showProviderDataSharingDetails,
                onCancel: dismissAddProvider
            )
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.top, isKeyboardPresented ? 12 : 0)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .zIndex(10)
    }

    private func requestProviderConnection() {
        KeyboardDismissal.dismiss()
        guard let selectedPlatform else {
            addProviderStatus = .failed("Select a provider before connecting.")
            return
        }

        guard selectedTier != nil else {
            addProviderStatus = .failed("Select a performance tier before connecting.")
            return
        }

        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            addProviderStatus = .failed("Enter an API key before connecting.")
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
            addProviderStatus = .failed("Select the provider again and retry.")
            return
        }

        providerStore.grantDataConsent(for: platform)
        providerAwaitingConsent = nil
        connectProvider()
    }

    private func connectProvider() {
        guard let selectedPlatform, let selectedTier else {
            addProviderStatus = .failed("Complete the provider settings and retry.")
            return
        }

        Task {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                addProviderStatus = .testing
            }

            do {
                try await providerStore.connect(
                    platform: selectedPlatform,
                    tier: selectedTier,
                    apiKey: apiKey
                )

                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        resetAddProviderForm()
                        isAddProviderPresented = false
                    }
                }
            } catch let error as ProviderConnectionError {
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        addProviderStatus = .failed(error.localizedDescription)
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        addProviderStatus = .failed(
                            "Could not test the provider. Check your network and try again.")
                    }
                }
            }
        }
    }

    private func presentAddProvider() {
        resetAddProviderForm()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isAddProviderPresented = true
        }
    }

    private func dismissAddProvider() {
        guard addProviderStatus.isTesting == false else {
            return
        }

        KeyboardDismissal.dismiss()
        providerAwaitingConsent = nil
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            isAddProviderPresented = false
        }
    }

    private func dismissAddProviderForTabChange() {
        guard isAddProviderPresented else {
            return
        }

        isAddProviderPresented = false
        providerAwaitingConsent = nil
        if addProviderStatus.isTesting == false {
            resetAddProviderForm()
        }
    }

    private func resetAddProviderForm() {
        selectedPlatform = nil
        selectedTier = nil
        apiKey = ""
        providerAwaitingConsent = nil
        addProviderStatus = .idle
    }

    private var removeProviderTitle: String {
        "Remove \(providerToRemove?.name ?? "provider")?"
    }

    private var removeProviderMessage: String {
        guard providerToRemove != nil else {
            return ""
        }

        return "FrameReply will remove the saved API key from this device."
    }

    private func removeSelectedProvider() {
        guard let providerToRemove else {
            return
        }

        do {
            try withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                try providerStore.remove(platform: providerToRemove.platform)
            }
        } catch {
            providerRemovalError = "The saved API key couldn’t be deleted. Nothing was changed."
        }

        self.providerToRemove = nil
    }

    private var privacyAndDataSection: some View {
        Button(action: onPrivacyAndDataTap) {
            settingsNavigationLabel(
                title: "Privacy & Data",
                subtitle: "Sharing permissions and local data",
                symbol: "hand.raised.fill"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("privacy-and-data")
    }

    private func settingsNavigationLabel(
        title: String,
        subtitle: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FrameReplyColor.primary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FrameReplyColor.outline)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 64)
        .background(Color.white.opacity(0.42))
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
