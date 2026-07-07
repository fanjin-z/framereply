//
//  ProviderCard.swift
//  zeptly
//

import SwiftUI

struct ProviderCard: View {
    let provider: ProviderConnection
    let isActive: Bool
    let onActivate: () -> Void
    let onModelChange: (ProviderModel) -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: isActive ? .top : .center, spacing: 14) {
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 42, height: 42)
                    .shadow(color: RezplyColor.primaryContainer.opacity(0.18), radius: 12, x: 0, y: 8)
                    .overlay {
                        Image(systemName: provider.symbolName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(RezplyColor.primary)
                    }

                VStack(alignment: .leading, spacing: 7) {
                    Text(provider.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(RezplyColor.onSurface)

                    if isActive {
                        PillChip(title: provider.modelName, tint: RezplyColor.primary)
                    }
                }

                Spacer()

                Toggle("", isOn: activeBinding)
                    .labelsHidden()
                    .tint(RezplyColor.primary)
                    .allowsHitTesting(isActive == false)
                    .accessibilityLabel("Use \(provider.name)")
                    .accessibilityHint(isActive ? "Currently active" : "Makes this provider active")
            }

            if isActive {
                SettingStatusRow(title: "Model") {
                    modelMenu
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.white.opacity(0.42))
        }
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { isActive },
            set: { newValue in
                if newValue, isActive == false {
                    onActivate()
                }
            }
        )
    }

    private var modelMenu: some View {
        Menu {
            ForEach(provider.platform.supportedModels) { model in
                Button {
                    onModelChange(model)
                } label: {
                    Text(model.rawValue)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(provider.model.displayName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .buttonStyle(.plain)
    }
}
