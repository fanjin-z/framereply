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

                    PillChip(title: provider.model, tint: RezplyColor.primary)
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
                            .fill(provider.isEnabled ? RezplyColor.connected : RezplyColor.outlineVariant)
                            .frame(width: 8, height: 8)
                        Text(provider.isEnabled ? "Connected" : "Paused")
                    }
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
}
