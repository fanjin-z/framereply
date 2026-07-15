//
//  SettingsView.swift
//  zeptly
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var providerStore: ProviderStore
    let isActive: Bool

    @State private var selectedPlatform: ProviderPlatform?
    @State private var selectedTier: ProviderTier?
    @State private var apiKey = ""
    @State private var addProviderStatus: AddProviderStatus = .idle
    @State private var isAddProviderPresented = false
    @State private var isKeyboardPresented = false
    @State private var providerToRemove: ProviderConnection?
    @State private var providerRemovalError: String?

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
    }

    private var providerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    providerHeader
                    providerContent
                }

                shortcutSection
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
                            .fill(RezplyColor.primary)
                    }
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Add model provider")
        }
        .foregroundStyle(RezplyColor.primary)
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
                            .foregroundStyle(RezplyColor.primary)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Add model provider")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(RezplyColor.onSurface)

                            Text("Connect OpenAI or a supported vision provider.")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(RezplyColor.onSurfaceVariant)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.white.opacity(0.42))
                    }
                }
                .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .medium))
                Text("Shortcuts")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
            }
            .foregroundStyle(RezplyColor.primary)

            Text(
                "Add one or both. Each imports recent messages and shows two suggested replies."
            )
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(RezplyColor.onSurfaceVariant)
            .fixedSize(horizontal: false, vertical: true)

            shortcutWorkflowCard(
                title: "Images",
                description:
                    "Share 1–8 screenshots or photos from one chat, or run the shortcut to capture the screen.",
                symbol: "photo.on.rectangle.angled",
                routes: [
                    ("square.and.arrow.up", "Share images → replies"),
                    ("hand.tap", "Run → screenshot → replies")
                ],
                buttonTitle: "Add Image Shortcut",
                installation: ShortcutInstallationCatalog.images
            )

            shortcutWorkflowCard(
                title: "Text",
                description:
                    "Share selected message text when your chat app supports it, or copy messages and run the shortcut.",
                symbol: "text.bubble",
                routes: [
                    ("square.and.arrow.up", "Share text → replies"),
                    ("doc.on.clipboard", "Copy messages → run → replies")
                ],
                buttonTitle: "Add Text Shortcut",
                installation: ShortcutInstallationCatalog.text
            )

            Text(
                "Run installed shortcuts from Spotlight, the Action button, Back Tap, the Home Screen, Siri, or Shortcuts."
            )
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(RezplyColor.onSurfaceVariant)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                "Images and message text are sent to your selected model provider for analysis. Zeptly does not save source images or raw imported text."
            )
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(RezplyColor.outline)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcutWorkflowCard(
        title: String,
        description: String,
        symbol: String,
        routes: [(symbol: String, text: String)],
        buttonTitle: String,
        installation: ShortcutInstallationDefinition
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 42, height: 42)
                    .shadow(
                        color: RezplyColor.primaryContainer.opacity(0.18), radius: 12, x: 0,
                        y: 8
                    )
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(RezplyColor.primary)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)

                    Text(description)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                    Label {
                        Text(route.text)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    } icon: {
                        Image(systemName: route.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18)
                    }
                    .foregroundStyle(RezplyColor.onSurfaceVariant)
                }
            }
            .accessibilityElement(children: .combine)

            shortcutInstallControl(
                installation: installation,
                buttonTitle: buttonTitle
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.white.opacity(0.42))
        }
    }

    @ViewBuilder
    private func shortcutInstallControl(
        installation: ShortcutInstallationDefinition,
        buttonTitle: String
    ) -> some View {
        if let installationURL = installation.installationURL {
            Link(destination: installationURL) {
                shortcutInstallLabel(title: buttonTitle, symbol: "arrow.up.forward.app")
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Install \(installation.title)")
            .accessibilityHint("Opens the \(installation.title) shortcut preview")
        } else {
            #if DEBUG
                Label("Installer unavailable in this build", systemImage: "hammer")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(RezplyColor.outline)
                    .accessibilityLabel("\(installation.title) installer unavailable in this build")
            #endif
        }
    }

    private func shortcutInstallLabel(title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .background(RezplyColor.primary)
        .clipShape(Capsule())
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
                onConnect: connectProvider,
                onCancel: dismissAddProvider
            )
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.top, isKeyboardPresented ? 12 : 0)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .zIndex(10)
    }

    private func connectProvider() {
        KeyboardDismissal.dismiss()
        guard let selectedPlatform else {
            addProviderStatus = .failed("Select a provider before saving.")
            return
        }

        guard let selectedTier else {
            addProviderStatus = .failed("Select a performance tier before saving.")
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
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            isAddProviderPresented = false
        }
    }

    private func dismissAddProviderForTabChange() {
        guard isAddProviderPresented else {
            return
        }

        isAddProviderPresented = false
        if addProviderStatus.isTesting == false {
            resetAddProviderForm()
        }
    }

    private func resetAddProviderForm() {
        selectedPlatform = nil
        selectedTier = nil
        apiKey = ""
        addProviderStatus = .idle
    }

    private var removeProviderTitle: String {
        "Remove \(providerToRemove?.name ?? "provider")?"
    }

    private var removeProviderMessage: String {
        guard providerToRemove != nil else {
            return ""
        }

        return "Zeptly will remove the saved API key from this device."
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
}
