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

    var inlineMessage: (symbolName: String, text: Text, tint: Color)? {
        switch self {
        case .idle, .testing:
            nil
        case .connected:
            (
                "checkmark.circle.fill",
                Text("Provider connected and saved."),
                FrameReplyColor.connected
            )
        case .failed(let message):
            ("exclamationmark.triangle.fill", Text(verbatim: message), FrameReplyColor.peach)
        }
    }
}

struct AddProviderCard: View {
    @Binding var selectedPlatform: ProviderPlatform?
    @Binding var selectedTier: ProviderTier?
    @Binding var apiKey: String
    @Binding var status: AddProviderStatus

    let title: LocalizedStringResource?
    let onConnect: () -> Void
    let onShowDataSharingDetails: () -> Void
    let onCancel: (() -> Void)?

    @State private var isAPIKeyVisible = false

    private var isConnectDisabled: Bool {
        status.isTesting
            || selectedPlatform == nil
            || selectedTier == nil
            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || onCancel != nil {
                HStack(alignment: .top, spacing: 16) {
                    if let title {
                        Text(title)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(FrameReplyColor.onSurface)
                    }

                    Spacer()

                    if let onCancel {
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                                .frame(width: 44, height: 44)
                                .background {
                                    Circle()
                                        .fill(FrameReplyColor.fieldSurface)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("close-add-provider")
                        .disabled(status.isTesting)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                providerMenu
                tierSelector

                VStack(alignment: .leading, spacing: 7) {
                    Text("API Key")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(FrameReplyColor.onSurface)

                    HStack {
                        Group {
                            if isAPIKeyVisible {
                                TextField("Enter API key", text: $apiKey)
                            } else {
                                SecureField("Enter API key", text: $apiKey)
                            }
                        }
                        .font(.system(.body, design: .monospaced, weight: .regular))
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
                                .frame(width: 44, height: 44)
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
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FrameReplyColor.fieldSurface)
                    }

                    Label("Stored securely on this device.", systemImage: "lock.fill")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(FrameReplyColor.outline)
                }

                if selectedPlatform != nil {
                    Button("Data Sharing Details", systemImage: "info.circle") {
                        onShowDataSharingDetails()
                    }
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .accessibilityIdentifier("provider-data-sharing-details")
                }

                if let inlineMessage = status.inlineMessage {
                    HStack(spacing: 8) {
                        Image(systemName: inlineMessage.symbolName)
                            .font(.system(size: 13, weight: .bold))
                        inlineMessage.text
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
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
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 44)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FrameReplyColor.actionFill)
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
                .font(.system(.subheadline, design: .rounded, weight: .medium))
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
                    .font(.system(.body, design: .rounded, weight: .regular))
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
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FrameReplyColor.fieldSurface)
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
                .font(.system(.subheadline, design: .rounded, weight: .medium))
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
                        .font(.system(.body, design: .rounded, weight: .regular))
                        .foregroundStyle(
                            selectedTier == nil
                                ? FrameReplyColor.outline : FrameReplyColor.onSurface)

                        if let selectedPlatform, let selectedTier {
                            Text(selectedPlatform.modelSummary(for: selectedTier))
                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
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
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            FrameReplyColor.fieldSurface.opacity(selectedPlatform == nil ? 0.6 : 1))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Performance tier")
            .accessibilityValue(accessibilityTierValue)
            .disabled(availableTiers.isEmpty)

        }
    }

    private var accessibilityTierValue: String {
        guard let selectedPlatform, let selectedTier else {
            return String(localized: "Not selected")
        }
        let tierName = String(localized: selectedTier.localizedDisplayName)
        let modelName = selectedPlatform.modelSummary(for: selectedTier)
        return String(localized: "\(tierName), \(modelName)")
    }

}
