import SwiftUI
import UIKit

@MainActor
enum KeyboardDismissal {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    func keyboardDismissable() -> some View {
        modifier(KeyboardDismissalModifier())
    }
}

private struct KeyboardDismissalModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .background(KeyboardDismissTapInstaller().allowsHitTesting(false))
    }
}

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.attach(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: InstallerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private weak var recognizer: UITapGestureRecognizer?

        func attach(to window: UIWindow?) {
            guard let window, window !== installedWindow else { return }
            detach()

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)

            installedWindow = window
            self.recognizer = recognizer
        }

        func detach() {
            if let recognizer {
                installedWindow?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedWindow = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !touchedView.isInsideTextInput
        }

        @objc private func handleTap() {
            KeyboardDismissal.dismiss()
        }
    }
}

private extension UIView {
    var isInsideTextInput: Bool {
        var candidate: UIView? = self
        while let view = candidate {
            if view is UITextField || view is UITextView {
                return true
            }
            candidate = view.superview
        }
        return false
    }
}
