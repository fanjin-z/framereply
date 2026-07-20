//
//  FloatingBottomNavigation.swift
//  FrameReply
//

import SwiftUI

struct FloatingBottomNavigation: View {
    @Binding var selectedTab: AppTab

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    if accessibilityReduceMotion {
                        selectedTab = tab
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            selectedTab = tab
                        }
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(
                            systemName: selectedTab == tab
                                ? "\(tab.symbolName).fill" : tab.symbolName
                        )
                        .font(.system(size: 23, weight: .medium))
                        .frame(height: 24)

                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(0.4)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(
                        selectedTab == tab ? FrameReplyColor.primary : Color.black.opacity(0.78)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .frame(minHeight: 50)
                    .background {
                        if selectedTab == tab {
                            Capsule(style: .continuous)
                                .fill(FrameReplyColor.primaryContainer.opacity(0.8))
                                .shadow(
                                    color: FrameReplyColor.primaryContainer.opacity(0.4),
                                    radius: 15,
                                    x: 0, y: 8)
                        }
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .accessibilityIdentifier("app-tab-\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 560)
        .frame(minHeight: 66)
        .glassPanel(cornerRadius: 34)
    }
}
