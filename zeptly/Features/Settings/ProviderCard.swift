//
//  ProviderCard.swift
//  zeptly
//

import SwiftUI

struct ProviderCard: View {
    @Binding var provider: ProviderConnection

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
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

                    PillChip(title: provider.modelName, tint: RezplyColor.primary)
                }

                Spacer()

                Toggle("", isOn: $provider.isEnabled)
                    .labelsHidden()
                    .tint(RezplyColor.primary)
            }

            VStack(spacing: 14) {
                SettingStatusRow(title: "Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(provider.displayValidationState.tint)
                            .frame(width: 8, height: 8)
                        Text(provider.displayValidationState.title)
                    }
                }

                SettingStatusRow(title: "Model") {
                    modelMenu
                }

                SettingStatusRow(title: "Last synced") {
                    Text(provider.lastSynced)
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.white.opacity(0.42))
        }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(provider.platform.supportedModels) { model in
                Button {
                    provider.model = model
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
