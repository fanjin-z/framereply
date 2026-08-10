//
//  SettingsView.swift
//  FrameReply
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var providerStore: ProviderStore
    let isActive: Bool
    let onPersonalInfoTap: () -> Void
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
            VStack(alignment: .leading, spacing: 24) {
                personalInfoSection
                providerSection
                shortcutSection
                privacyAndDataSection
            }
            .padding(.top, 20)
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("settings-screen")
    }

    private var providerSection: some View {
        settingsSection {
            sectionHeader("Model Providers") {
                Button {
                    presentAddProvider()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.primary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add model provider")
                .accessibilityIdentifier("add-provider-header")
            }
        } content: {
            providerContent
        }
    }

    private var providerContent: some View {
        settingsSurface {
            if providerStore.providers.isEmpty {
                Button {
                    presentAddProvider()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(FrameReplyColor.primary)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Add model provider")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurface)

                            Text("Connect OpenAI or a supported vision provider.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 68)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("add-provider")
            } else {
                ForEach(Array(providerStore.providers.enumerated()), id: \.element.id) { entry in
                    ProviderCard(
                        provider: entry.element,
                        isActive: providerStore.activePlatform == entry.element.platform,
                        onActivate: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                providerStore.activate(platform: entry.element.platform)
                            }
                        },
                        onTierChange: { tier in
                            providerStore.setTier(tier, for: entry.element.platform)
                        },
                        onRemove: {
                            providerToRemove = entry.element
                        }
                    )

                    if entry.offset < providerStore.providers.count - 1 {
                        settingsDivider(leadingInset: 60)
                    }
                }
            }
        }
    }

    private var shortcutSection: some View {
        settingsSection {
            sectionHeader("Shortcuts")
        } content: {
            settingsSurface {
                shortcutInstallRow(
                    title: "Image Shortcut",
                    subtitle: "Import screenshots",
                    symbol: "photo.on.rectangle.angled",
                    installation: ShortcutInstallationCatalog.images
                )

                settingsDivider(leadingInset: 60)

                shortcutInstallRow(
                    title: "Text Shortcut",
                    subtitle: "Import copied messages",
                    symbol: "text.bubble",
                    installation: ShortcutInstallationCatalog.text
                )
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
                .frame(width: 32)

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
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
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
        settingsSection {
            sectionHeader("Privacy & Support")
        } content: {
            settingsSurface {
                Button(action: onPrivacyAndDataTap) {
                    settingsNavigationLabel(
                        title: "Privacy & Data",
                        subtitle: "Policies, support, and local data",
                        symbol: "hand.raised.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("privacy-and-data")
            }
        }
    }

    private var personalInfoSection: some View {
        settingsSection {
            sectionHeader("Personalization")
        } content: {
            settingsSurface {
                Button(action: onPersonalInfoTap) {
                    settingsNavigationLabel(
                        title: "Personal Info",
                        subtitle: "Names and details that help personalize replies.",
                        symbol: "person.text.rectangle"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("personal-info")
            }
        }
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
                .frame(width: 32)

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
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
    }

    private func settingsSection<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header()
            content()
        }
    }

    private func sectionHeader<Trailing: View>(
        _ title: LocalizedStringResource,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)

            Spacer()
            trailing()
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 24)
    }

    private func sectionHeader(_ title: LocalizedStringResource) -> some View {
        sectionHeader(title) {
            EmptyView()
        }
    }

    private func settingsSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.46))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func settingsDivider(leadingInset: CGFloat) -> some View {
        Divider()
            .overlay(FrameReplyColor.outlineVariant.opacity(0.5))
            .padding(.leading, leadingInset)
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
