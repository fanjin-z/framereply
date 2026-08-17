import SwiftUI
import UIKit

struct CompactSwipeRow<Content: View>: View {
    private let actionWidth: CGFloat = 82
    private let swipeProjectionTime: CGFloat = 0.2

    let isRevealed: Bool
    let onReveal: () -> Void
    let onClose: () -> Void
    let onAction: () -> Void
    let actionTitle: LocalizedStringResource
    let actionSystemImage: String
    let actionTint: Color
    let actionAccessibilityIdentifier: String
    let content: Content

    @State private var dragTranslation: CGFloat = 0

    init(
        isRevealed: Bool,
        onReveal: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onAction: @escaping () -> Void,
        actionTitle: LocalizedStringResource,
        actionSystemImage: String,
        actionTint: Color,
        actionAccessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.isRevealed = isRevealed
        self.onReveal = onReveal
        self.onClose = onClose
        self.onAction = onAction
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.actionTint = actionTint
        self.actionAccessibilityIdentifier = actionAccessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onAction) {
                VStack(spacing: 3) {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 16, weight: .semibold))
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
            }
            .buttonStyle(.plain)
            .opacity(isActionVisible ? 1 : 0)
            .allowsHitTesting(isRevealed)
            .accessibilityHidden(!isRevealed)
            .accessibilityIdentifier(actionAccessibilityIdentifier)

            content
                .offset(x: rowOffset)
                .gesture(
                    HorizontalPanGesture(
                        onChanged: { translation in
                            dragTranslation = translation
                        },
                        onEnded: finishSwipe,
                        onCancelled: {
                            dragTranslation = 0
                        }
                    )
                )
        }
        .background(alignment: .trailing) {
            actionTint
                .opacity(isActionVisible ? 1 : 0)
                .frame(width: actionWidth)
        }
        .background(FrameReplyColor.surfaceContainerLow)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.2), value: isRevealed)
    }

    private var isActionVisible: Bool {
        isRevealed || dragTranslation < 0
    }

    private var rowOffset: CGFloat {
        let restingOffset = isRevealed ? -actionWidth : 0
        return min(0, max(-actionWidth, restingOffset + dragTranslation))
    }

    private func finishSwipe(translation: CGFloat, velocity: CGFloat) {
        let restingOffset = isRevealed ? -actionWidth : 0
        let projectedTranslation = translation + velocity * swipeProjectionTime
        let projectedOffset = min(
            0,
            max(-actionWidth, restingOffset + projectedTranslation)
        )

        dragTranslation = 0
        if projectedOffset < -actionWidth / 2 {
            onReveal()
        } else {
            onClose()
        }
    }
}

extension View {
    func compactSwipeRowSurface(showsSeparator: Bool) -> some View {
        background(FrameReplyColor.surfaceContainerLow)
            .overlay(alignment: .bottom) {
                if showsSeparator {
                    Rectangle()
                        .fill(FrameReplyColor.outlineVariant.opacity(0.55))
                        .frame(height: 0.5)
                        .padding(.horizontal, 22)
                }
            }
    }
}

/// A pan gesture that fails before recognition unless the user's movement is
/// predominantly horizontal. Failing early leaves vertical drags to the
/// enclosing scroll view.
private struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
    let onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        let translation = recognizer.translation(in: recognizer.view).x

        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
                return false
            }

            let velocity = panGesture.velocity(in: panGesture.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }
    }
}
