//
//  FloatingBottomNavigation.swift
//  FrameReply
//

import SwiftUI

struct FloatingBottomNavigation: View {
    @Binding var selectedTab: AppTab

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Namespace private var selectionNamespace
    @ScaledMetric(relativeTo: .caption) private var symbolSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selectedTab == tab

                Button {
                    if accessibilityReduceMotion {
                        selectedTab = tab
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            selectedTab = tab
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(
                            systemName: isSelected
                                ? "\(tab.symbolName).fill" : tab.symbolName
                        )
                        .font(.system(size: symbolSize, weight: .semibold))
                        .frame(minHeight: 24)

                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                    }
                    .foregroundStyle(
                        isSelected
                            ? FrameReplyColor.primary : FrameReplyColor.onSurfaceVariant
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 5)
                    .contentShape(Capsule(style: .continuous))
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(FrameReplyColor.primaryContainer.opacity(0.42))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.36), lineWidth: 0.5)
                                }
                                .matchedGeometryEffect(
                                    id: "selected-tab",
                                    in: selectionNamespace
                                )
                        }
                    }
                }
                .buttonStyle(SoftPressButtonStyle())
                .accessibilityLabel(Text(tab.title))
                .accessibilityValue(isSelected ? Text("Current tab") : Text(""))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("app-tab-\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 560)
        .frame(minHeight: 64)
        .contentShape(Capsule(style: .continuous))
        .glassEffect(.regular, in: Capsule(style: .continuous))
    }
}
