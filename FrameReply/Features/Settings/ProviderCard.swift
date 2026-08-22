//
//  ProviderCard.swift
//  FrameReply
//

import SwiftUI

struct ProviderCard: View {
    let provider: ProviderConnection
    let isActive: Bool
    let onActivate: () -> Void
    let onTierChange: (ProviderTier) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    if isActive == false {
                        onActivate()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.white.opacity(0.72))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: provider.symbolName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(FrameReplyColor.primary)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurface)
                                .lineLimit(2)

                            Text(provider.platform.modelSummary(for: provider.tier))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)
                        selectionIndicator
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(provider.name)")
                .accessibilityValue(isActive ? "Selected" : "Not selected")
                .accessibilityHint(
                    isActive ? "Current model provider" : "Makes this provider active")

                Menu {
                    Button(
                        "Delete",
                        systemImage: "trash",
                        role: .destructive,
                        action: onRemove
                    )
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(FrameReplyColor.outline)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Provider actions for \(provider.name)")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)

            if showsPerformancePicker {
                Divider()
                    .overlay(FrameReplyColor.outlineVariant.opacity(0.5))
                    .padding(.leading, 60)

                SettingStatusRow(title: "Performance") {
                    tierMenu
                }
                .padding(.leading, 60)
                .padding(.trailing, 16)
                .frame(minHeight: 46)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityIdentifier("provider-row-\(provider.platform.rawValue)")
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(
                    isActive ? FrameReplyColor.connected : FrameReplyColor.outlineVariant,
                    lineWidth: 2
                )
                .frame(width: 24, height: 24)

            if isActive {
                Circle()
                    .fill(FrameReplyColor.connected)
                    .frame(width: 14, height: 14)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private var showsPerformancePicker: Bool {
        isActive && provider.platform.supportedTiers.count > 1
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
