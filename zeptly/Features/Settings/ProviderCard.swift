//
//  ProviderCard.swift
//  zeptly
//

import SwiftUI

struct ProviderCard: View {
    let provider: ProviderConnection
    let isActive: Bool
    let onActivate: () -> Void
    let onTierChange: (ProviderTier) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 42, height: 42)
                    .shadow(
                        color: RezplyColor.primaryContainer.opacity(0.18), radius: 12, x: 0, y: 8
                    )
                    .overlay {
                        Image(systemName: provider.symbolName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(RezplyColor.primary)
                    }

                Text(provider.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)

                Spacer()

                HStack(spacing: 8) {
                    selectionControl

                    Menu {
                        Button(
                            "Delete",
                            systemImage: "trash",
                            role: .destructive,
                            action: onRemove
                        )
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .bold))
                            .rotationEffect(.degrees(90))
                            .foregroundStyle(RezplyColor.outline)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Provider actions for \(provider.name)")
                }
            }

            if isActive {
                SettingStatusRow(title: "Performance") {
                    tierMenu
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

    private var selectionControl: some View {
        Button {
            if isActive == false {
                onActivate()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(
                        isActive ? RezplyColor.connected : RezplyColor.outlineVariant,
                        lineWidth: 2
                    )
                    .frame(width: 24, height: 24)

                if isActive {
                    Circle()
                        .fill(RezplyColor.connected)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use \(provider.name)")
        .accessibilityValue(isActive ? "Selected" : "Not selected")
        .accessibilityHint(isActive ? "Current model provider" : "Makes this provider active")
    }

    private var tierMenu: some View {
        Menu {
            ForEach(provider.platform.supportedTiers) { tier in
                Button {
                    onTierChange(tier)
                } label: {
                    Text(tier.displayName)
                    Text(provider.platform.modelSummary(for: tier))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(
                    "\(provider.tier.displayName) · \(provider.platform.modelSummary(for: provider.tier))"
                )
                .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Performance tier")
        .accessibilityValue(
            "\(provider.tier.displayName), \(provider.platform.modelSummary(for: provider.tier))"
        )
    }
}
