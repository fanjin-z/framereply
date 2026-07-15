//
//  AddProviderCard.swift
//  zeptly
//

import SwiftUI

enum AddProviderStatus {
    case idle
    case testing
    case connected
    case failed(String)

    var isTesting: Bool {
        if case .testing = self {
            return true
        }
        return false
    }

    var inlineMessage: (symbolName: String, text: String, tint: Color)? {
        switch self {
        case .idle, .testing:
            nil
        case .connected:
            ("checkmark.circle.fill", "Provider connected and saved.", RezplyColor.connected)
        case .failed(let message):
            ("exclamationmark.triangle.fill", message, RezplyColor.peach)
        }
    }
}

struct AddProviderCard: View {
    @Binding var selectedPlatform: ProviderPlatform?
    @Binding var selectedTier: ProviderTier?
    @Binding var apiKey: String
    @Binding var status: AddProviderStatus

    let onConnect: () -> Void
    let onCancel: () -> Void

    @State private var isAPIKeyVisible = false

    private var isConnectDisabled: Bool {
        status.isTesting
            || selectedPlatform == nil
            || selectedTier == nil
            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                Text("Add Provider")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RezplyColor.onSurfaceVariant)
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(Color.white.opacity(0.58))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .disabled(status.isTesting)
            }

            VStack(alignment: .leading, spacing: 12) {
                providerMenu
                tierSelector

                VStack(alignment: .leading, spacing: 7) {
                    Text("API Key")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)

                    HStack {
                        Group {
                            if isAPIKeyVisible {
                                TextField("Enter API key", text: $apiKey)
                            } else {
                                SecureField("Enter API key", text: $apiKey)
                            }
                        }
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit { KeyboardDismissal.dismiss() }

                        Button {
                            isAPIKeyVisible.toggle()
                        } label: {
                            Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(RezplyColor.onSurfaceVariant)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isAPIKeyVisible ? "Hide API key" : "Show API key")
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.white.opacity(0.56))
                    }

                }

                if let inlineMessage = status.inlineMessage {
                    HStack(spacing: 8) {
                        Image(systemName: inlineMessage.symbolName)
                            .font(.system(size: 13, weight: .bold))
                        Text(inlineMessage.text)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineSpacing(2)
                    }
                    .foregroundStyle(inlineMessage.tint)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    onConnect()
                } label: {
                    HStack(spacing: 9) {
                        if status.isTesting {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(status.isTesting ? "Saving..." : "Save")
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 44)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.primary)
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .disabled(isConnectDisabled)
                .opacity(isConnectDisabled ? 0.56 : 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 26)
    }

    private var providerMenu: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Provider")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)

            Menu {
                ForEach(ProviderPlatform.allCases) { platform in
                    Button {
                        selectedPlatform = platform
                        selectedTier = platform.defaultTier
                    } label: {
                        Text(platform.displayName)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: selectedPlatform?.symbolName ?? "building.2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RezplyColor.primary)

                    Text(selectedPlatform?.displayName ?? "Select provider")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(
                            selectedPlatform == nil ? RezplyColor.outline : RezplyColor.onSurface)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RezplyColor.onSurfaceVariant)
                }
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.white.opacity(0.56))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var tierSelector: some View {
        let availableTiers = selectedPlatform?.supportedTiers ?? []

        return VStack(alignment: .leading, spacing: 7) {
            Text("Performance")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)

            Menu {
                ForEach(availableTiers) { tier in
                    Button {
                        selectedTier = tier
                    } label: {
                        if let selectedPlatform {
                            Text(tier.displayName)
                            Text(selectedPlatform.modelSummary(for: tier))
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RezplyColor.primary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedTier?.displayName ?? "Select performance")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(
                                selectedTier == nil ? RezplyColor.outline : RezplyColor.onSurface)

                        if let selectedPlatform, let selectedTier {
                            Text(selectedPlatform.modelSummary(for: selectedTier))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(RezplyColor.onSurfaceVariant)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RezplyColor.onSurfaceVariant)
                }
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.white.opacity(selectedPlatform == nil ? 0.34 : 0.56))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Performance tier")
            .accessibilityValue(accessibilityTierValue)
            .disabled(availableTiers.isEmpty)

            Text(
                "The underlying model may be updated automatically within your selected performance tier."
            )
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(RezplyColor.outline)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityTierValue: String {
        guard let selectedPlatform, let selectedTier else { return "Not selected" }
        return "\(selectedTier.displayName), \(selectedPlatform.modelSummary(for: selectedTier))"
    }
}
