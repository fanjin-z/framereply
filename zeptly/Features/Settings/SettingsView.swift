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
    @State private var selectedModel: ProviderModel?
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
        .onChange(of: selectedModel) { _, _ in
            if case .connected = addProviderStatus {
                addProviderStatus = .idle
            }
        }
        .onChange(of: isActive) { _, isActive in
            if isActive == false {
                dismissAddProviderForTabChange()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                isKeyboardPresented = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
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
                    Text("Screenshot images are uploaded transiently to your selected model provider for analysis. Zeptly does not save the image.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(RezplyColor.outline)
                        .fixedSize(horizontal: false, vertical: true)
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
                        onModelChange: { model in
                            providerStore.setModel(model, for: provider.platform)
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
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 20, weight: .medium))
                Text("Screenshot Shortcut")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
            }
            .foregroundStyle(RezplyColor.primary)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Circle()
                        .fill(Color.white.opacity(0.78))
                        .frame(width: 42, height: 42)
                        .shadow(color: RezplyColor.primaryContainer.opacity(0.18), radius: 12, x: 0, y: 8)
                        .overlay {
                            Image(systemName: "photo.badge.arrow.down")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(RezplyColor.primary)
                        }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Capture with Zeptly")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)

                        Text("Takes a screenshot, imports the visible chat, and shows two suggested replies.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                shortcutInstallControl
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.white.opacity(0.42))
            }
        }
    }

    @ViewBuilder
    private var shortcutInstallControl: some View {
        if let installationURL = ScreenshotShortcutConfiguration.installationURL {
            Link(destination: installationURL) {
                shortcutInstallLabel(title: "Add Shortcut", symbol: "arrow.up.forward.app")
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityHint("Opens the Capture with Zeptly shortcut preview")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: {}) {
                    shortcutInstallLabel(title: "Add Shortcut", symbol: "arrow.up.forward.app")
                }
                .buttonStyle(SoftPressButtonStyle())
                .disabled(true)

                Text("The installer link has not been configured yet.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(RezplyColor.outline)
            }
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
                selectedModel: $selectedModel,
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

        guard let selectedModel else {
            addProviderStatus = .failed("Select a model before saving.")
            return
        }

        Task {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                addProviderStatus = .testing
            }

            do {
                try await providerStore.connect(
                    platform: selectedPlatform,
                    model: selectedModel,
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
                        addProviderStatus = .failed("Could not test the provider. Check your network and try again.")
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
        selectedModel = nil
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
