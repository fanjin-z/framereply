//
//  SettingsView.swift
//  zeptly
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var providerStore: ProviderStore
    let isActive: Bool

    @State private var selectedPlatform: ProviderPlatform?
    @State private var selectedModel: ProviderModel?
    @State private var apiKey = ""
    @State private var addProviderStatus: AddProviderStatus = .idle
    @State private var isAddProviderPresented = false

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
    }

    private var providerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    providerHeader
                    providerContent
                    Text("Screenshot imports run OCR on this device. Only the extracted text and layout are sent to your selected model provider; screenshots are never saved or uploaded.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(RezplyColor.outline)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

                            Text("Connect DeepSeek or another supported provider.")
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
                        }
                    )
                }
            }
        }
    }

    private var addProviderPopup: some View {
        ZStack {
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
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .zIndex(10)
    }

    private func connectProvider() {
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
}
