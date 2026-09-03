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

    @Environment(\.openURL) private var openURL
    @State private var isAddProviderPresented = false
    @State private var isProviderConnectionInProgress = false
    @State private var isKeyboardPresented = false
    @State private var providerToRemove: ProviderConnection?
    @State private var providerRemovalError: String?
    @State private var isLanguageSettingsErrorPresented = false

    var body: some View {
        ZStack {
            providerList

            if isAddProviderPresented {
                addProviderPopup
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
        .alert("Couldn’t Open Settings", isPresented: $isLanguageSettingsErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open Settings > Apps > FrameReply > Language to choose the app language.")
        }
    }

    private var providerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                personalInfoSection
                providerSection
                ShortcutSetupSection()
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

    private var addProviderPopup: some View {
        ZStack(alignment: isKeyboardPresented ? .top : .center) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissAddProvider()
                }

            ProviderConnectionView(
                providerStore: providerStore,
                isConnectionInProgress: $isProviderConnectionInProgress,
                title: "Add Provider",
                onConnected: dismissAddProviderAfterConnection,
                onCancel: dismissAddProvider
            )
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.top, isKeyboardPresented ? 12 : 0)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .zIndex(10)
    }

    private func presentAddProvider() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isAddProviderPresented = true
        }
    }

    private func dismissAddProvider() {
        guard isProviderConnectionInProgress == false else {
            return
        }

        KeyboardDismissal.dismiss()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            isAddProviderPresented = false
        }
    }

    private func dismissAddProviderForTabChange() {
        guard isAddProviderPresented else {
            return
        }

        isAddProviderPresented = false
    }

    private func dismissAddProviderAfterConnection() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isAddProviderPresented = false
        }
    }

    private var removeProviderTitle: LocalizedStringResource {
        let providerName = providerToRemove?.name ?? String(localized: "provider")
        return "Remove \(providerName)?"
    }

    private var removeProviderMessage: LocalizedStringResource {
        "FrameReply will remove the saved API key from this device."
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
            providerRemovalError = String(
                localized: "The saved API key couldn’t be deleted. Nothing was changed."
            )
        }

        self.providerToRemove = nil
    }

    private var privacyAndDataSection: some View {
        settingsSection {
            sectionHeader("App & Support")
        } content: {
            settingsSurface {
                Button(action: openLanguageSettings) {
                    settingsNavigationLabel(
                        title: "App Language",
                        subtitle: effectiveAppLanguageName,
                        symbol: "globe"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens iPhone Settings to change the app language.")
                .accessibilityIdentifier("app-language")

                settingsDivider(leadingInset: 60)

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
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
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

    private var effectiveAppLanguageName: LocalizedStringResource {
        if LocalizationContext.current.languageIdentifier.hasPrefix("zh-Hans") {
            return "Simplified Chinese"
        }
        return "English"
    }

    private func openLanguageSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            isLanguageSettingsErrorPresented = true
            return
        }

        openURL(url) { didOpen in
            if didOpen == false {
                isLanguageSettingsErrorPresented = true
            }
        }
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

}
