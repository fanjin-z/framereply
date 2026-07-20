//
//  AddProviderCard.swift
//  FrameReply
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
            ("checkmark.circle.fill", "Provider connected and saved.", FrameReplyColor.connected)
        case .failed(let message):
            ("exclamationmark.triangle.fill", message, FrameReplyColor.peach)
        }
    }
}

struct AddProviderCard: View {
    @Binding var selectedPlatform: ProviderPlatform?
    @Binding var selectedTier: ProviderTier?
    @Binding var apiKey: String
    @Binding var status: AddProviderStatus

    let onConnect: () -> Void
    let onShowDataSharingDetails: () -> Void
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
                    .foregroundStyle(FrameReplyColor.onSurface)

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(Color.white.opacity(0.58))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("close-add-provider")
                .disabled(status.isTesting)
            }

            VStack(alignment: .leading, spacing: 12) {
                providerMenu
                tierSelector

                VStack(alignment: .leading, spacing: 7) {
                    Text("API Key")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurface)

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
                        .accessibilityIdentifier("provider-api-key")
                        .onSubmit { KeyboardDismissal.dismiss() }

                        Button {
                            isAPIKeyVisible.toggle()
                        } label: {
                            Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            isAPIKeyVisible
                                ? LocalizedStringResource("Hide API key")
                                : LocalizedStringResource("Show API key")
                        )
                    }
                    .padding(.horizontal, 18)
                    .frame(minHeight: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.white.opacity(0.56))
                    }

                    Label("Stored securely on this device.", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(FrameReplyColor.outline)
                }

                if selectedPlatform != nil {
                    Button("Data Sharing Details", systemImage: "info.circle") {
                        onShowDataSharingDetails()
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .accessibilityIdentifier("provider-data-sharing-details")
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
                        Text(
                            status.isTesting
                                ? LocalizedStringResource("Connecting...")
                                : LocalizedStringResource("Connect")
                        )
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 44)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FrameReplyColor.primary)
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .accessibilityIdentifier("connect-provider")
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
                .foregroundStyle(FrameReplyColor.onSurface)

            Menu {
                ForEach(ProviderPlatform.availableCases) { platform in
                    Button {
                        selectedPlatform = platform
                        selectedTier = platform.defaultTier
                    } label: {
                        Text(platform.displayName)
                    }
                    .accessibilityIdentifier("provider-choice-\(platform.rawValue)")
                }
            } label: {
                HStack {
                    Image(systemName: selectedPlatform?.symbolName ?? "building.2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FrameReplyColor.primary)

                    Group {
                        if let selectedPlatform {
                            Text(verbatim: selectedPlatform.displayName)
                        } else {
                            Text("Select provider")
                        }
                    }
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(
                        selectedPlatform == nil
                            ? FrameReplyColor.outline : FrameReplyColor.onSurface)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 46)
                .background {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.white.opacity(0.56))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("select-provider")
        }
    }

    private var tierSelector: some View {
        let availableTiers = selectedPlatform?.supportedTiers ?? []

        return VStack(alignment: .leading, spacing: 7) {
            Text("Performance")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)

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
                        .foregroundStyle(FrameReplyColor.primary)

                    VStack(alignment: .leading, spacing: 3) {
                        Group {
                            if let selectedTier {
                                Text(selectedTier.localizedDisplayName)
                            } else {
                                Text("Select performance")
                            }
                        }
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(
                            selectedTier == nil
                                ? FrameReplyColor.outline : FrameReplyColor.onSurface)

                        if let selectedPlatform, let selectedTier {
                            Text(selectedPlatform.modelSummary(for: selectedTier))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 50)
                .background {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.white.opacity(selectedPlatform == nil ? 0.34 : 0.56))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Performance tier")
            .accessibilityValue(accessibilityTierValue)
            .disabled(availableTiers.isEmpty)

        }
    }

    private var accessibilityTierValue: String {
        guard let selectedPlatform, let selectedTier else { return "Not selected" }
        return "\(selectedTier.displayName), \(selectedPlatform.modelSummary(for: selectedTier))"
    }

}
