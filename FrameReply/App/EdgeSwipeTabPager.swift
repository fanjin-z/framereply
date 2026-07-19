//
//  EdgeSwipeTabPager.swift
//  FrameReply
//

import SwiftUI

struct EdgeSwipeTabPager<Content: View>: View {
    @Binding var selectedTab: AppTab

    let isSwipeEnabled: Bool
    @ViewBuilder let content: (AppTab, Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases) { tab in
                        content(tab, selectedTab == tab)
                            .frame(width: pageWidth, height: proxy.size.height)
                            .accessibilityHidden(selectedTab != tab)
                    }
                }
                .frame(
                    width: pageWidth * CGFloat(AppTab.allCases.count),
                    alignment: .leading
                )
                .offset(
                    x: -CGFloat(selectedTab.index) * pageWidth + dragOffset
                )
            }
            .frame(
                width: pageWidth,
                height: proxy.size.height,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .clipped()
            .simultaneousGesture(
                edgeSwipeGesture(pageWidth: pageWidth),
                isEnabled: isSwipeEnabled
            )
        }
    }

    private func edgeSwipeGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                dragOffset = TabSwipeNavigation.dragOffset(
                    from: selectedTab,
                    startX: value.startLocation.x,
                    pageWidth: pageWidth,
                    translation: value.translation
                )
            }
            .onEnded { value in
                let destination = TabSwipeNavigation.destination(
                    from: selectedTab,
                    startX: value.startLocation.x,
                    pageWidth: pageWidth,
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                )

                if accessibilityReduceMotion {
                    selectedTab = destination
                    dragOffset = 0
                } else {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                        selectedTab = destination
                        dragOffset = 0
                    }
                }
            }
    }
}

enum TabSwipeDirection: Equatable {
    case previous
    case next
}

enum TabSwipeNavigation {
    static let edgeActivationWidth: CGFloat = 24
    static let horizontalDominance: CGFloat = 1.2
    static let completionFraction: CGFloat = 0.25
    static let maximumCompletionDistance: CGFloat = 120
    static let boundaryResistance: CGFloat = 0.18
    static let maximumBoundaryOffset: CGFloat = 44

    static func direction(
        startX: CGFloat,
        pageWidth: CGFloat,
        translation: CGSize
    ) -> TabSwipeDirection? {
        guard pageWidth > 0 else {
            return nil
        }

        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        guard horizontalDistance > verticalDistance * horizontalDominance else {
            return nil
        }

        if startX <= edgeActivationWidth, translation.width > 0 {
            return .previous
        }

        if startX >= pageWidth - edgeActivationWidth, translation.width < 0 {
            return .next
        }

        return nil
    }

    static func dragOffset(
        from tab: AppTab,
        startX: CGFloat,
        pageWidth: CGFloat,
        translation: CGSize
    ) -> CGFloat {
        guard
            let direction = direction(
                startX: startX,
                pageWidth: pageWidth,
                translation: translation
            )
        else {
            return 0
        }

        if adjacentTab(from: tab, direction: direction) != nil {
            let distance = min(abs(translation.width), pageWidth)
            return direction == .previous ? distance : -distance
        }

        let resistedDistance = min(
            abs(translation.width) * boundaryResistance,
            maximumBoundaryOffset
        )
        return direction == .previous ? resistedDistance : -resistedDistance
    }

    static func destination(
        from tab: AppTab,
        startX: CGFloat,
        pageWidth: CGFloat,
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> AppTab {
        guard
            let direction = direction(
                startX: startX,
                pageWidth: pageWidth,
                translation: translation
            ), let adjacentTab = adjacentTab(from: tab, direction: direction)
        else {
            return tab
        }

        let threshold = min(
            pageWidth * completionFraction,
            maximumCompletionDistance
        )
        let directionSign: CGFloat = direction == .previous ? 1 : -1
        let translationInDirection = translation.width * directionSign
        let predictionInDirection = predictedEndTranslation.width * directionSign

        guard translationInDirection >= threshold || predictionInDirection >= threshold else {
            return tab
        }

        return adjacentTab
    }

    private static func adjacentTab(
        from tab: AppTab,
        direction: TabSwipeDirection
    ) -> AppTab? {
        switch direction {
        case .previous:
            tab.previous
        case .next:
            tab.next
        }
    }
}
