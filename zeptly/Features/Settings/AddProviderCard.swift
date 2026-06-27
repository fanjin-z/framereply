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
        case let .failed(message):
            ("exclamationmark.triangle.fill", message, RezplyColor.peach)
        }
    }
}

struct AddProviderCard: View {
    @Binding var selectedPlatform: ProviderPlatform?
    @Binding var selectedModel: ProviderModel?
    @Binding var apiKey: String
    @Binding var status: AddProviderStatus

    let onConnect: () -> Void
    let onCancel: () -> Void

    @State private var isAPIKeyVisible = false

    private var isConnectDisabled: Bool {
        status.isTesting
            || selectedPlatform?.isConnectable != true
            || selectedModel == nil
            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add Provider")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)

                    Text("Connect a model provider with your own API key.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .lineSpacing(2)
                        .foregroundStyle(RezplyColor.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }

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

            VStack(alignment: .leading, spacing: 18) {
                providerMenu
                modelSelector

                VStack(alignment: .leading, spacing: 9) {
                    Text("API Key")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)

                    HStack {
                        Group {
                            if isAPIKeyVisible {
                                TextField("sk-...", text: $apiKey)
                            } else {
                                SecureField("sk-...", text: $apiKey)
                            }
                        }
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)

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
                    .frame(height: 50)
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
                    .frame(height: 48)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.primary)
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .disabled(isConnectDisabled)
                .opacity(isConnectDisabled ? 0.56 : 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 8)
            }
        }
        .padding(22)
        .glassPanel(cornerRadius: 26)
    }

    private var providerMenu: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Provider")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)

            Menu {
                ForEach(ProviderPlatform.allCases) { platform in
                    Button {
                        selectedPlatform = platform
                        selectedModel = nil
                    } label: {
                        Text(platform.isConnectable ? platform.displayName : "\(platform.displayName) - Coming soon")
                    }
                    .disabled(platform.isConnectable == false)
                }
            } label: {
                HStack {
                    Image(systemName: selectedPlatform?.symbolName ?? "building.2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RezplyColor.primary)

                    Text(selectedPlatform?.displayName ?? "Select provider")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(selectedPlatform == nil ? RezplyColor.outline : RezplyColor.onSurface)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RezplyColor.onSurfaceVariant)
                }
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.white.opacity(0.56))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var modelSelector: some View {
        let availableModels = selectedPlatform?.supportedModels ?? []

        return VStack(alignment: .leading, spacing: 9) {
            Text("Model")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)

            Menu {
                ForEach(availableModels) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        Text("\(model.displayName) - \(model.rawValue)")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RezplyColor.primary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedModel?.displayName ?? "Select model")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(selectedModel == nil ? RezplyColor.outline : RezplyColor.onSurface)

                        if let selectedModel {
                            Text(selectedModel.rawValue)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                .frame(height: 54)
                .background {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.white.opacity(selectedPlatform == nil ? 0.34 : 0.56))
                }
            }
            .buttonStyle(.plain)
            .disabled(availableModels.isEmpty)
        }
    }
}
