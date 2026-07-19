//
//  InteractiveSwipeBack.swift
//  FrameReply
//

import SwiftUI
import UIKit

extension View {
    func interactiveSwipeBackEnabled() -> some View {
        background {
            InteractiveSwipeBackInstaller()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct InteractiveSwipeBackInstaller: UIViewControllerRepresentable {
    func makeCoordinator() -> InteractivePopGestureDelegate {
        InteractivePopGestureDelegate()
    }

    func makeUIViewController(context: Context) -> NavigationControllerResolver {
        let resolver = NavigationControllerResolver()
        resolver.onResolve = { navigationController in
            context.coordinator.install(on: navigationController)
        }
        return resolver
    }

    func updateUIViewController(
        _ uiViewController: NavigationControllerResolver,
        context: Context
    ) {
        uiViewController.resolveNavigationController()
    }

    static func dismantleUIViewController(
        _ uiViewController: NavigationControllerResolver,
        coordinator: InteractivePopGestureDelegate
    ) {
        uiViewController.onResolve = nil
        coordinator.restorePreviousDelegate()
    }
}

private final class NavigationControllerResolver: UIViewController {
    var onResolve: ((UINavigationController) -> Void)?

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        resolveNavigationController()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resolveNavigationController()
    }

    func resolveNavigationController() {
        guard let navigationController else {
            return
        }

        onResolve?(navigationController)
    }
}

final class InteractivePopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var navigationController: UINavigationController?
    private var previousDelegate: (any UIGestureRecognizerDelegate)?

    func install(on navigationController: UINavigationController) {
        guard let gestureRecognizer = navigationController.interactivePopGestureRecognizer else {
            return
        }

        if self.navigationController !== navigationController {
            restorePreviousDelegate()
            self.navigationController = navigationController
            previousDelegate = gestureRecognizer.delegate
        }

        gestureRecognizer.isEnabled = true
        gestureRecognizer.delegate = self
    }

    func restorePreviousDelegate() {
        guard let gestureRecognizer = navigationController?.interactivePopGestureRecognizer else {
            navigationController = nil
            previousDelegate = nil
            return
        }

        if gestureRecognizer.delegate === self {
            gestureRecognizer.delegate = previousDelegate
        }

        navigationController = nil
        previousDelegate = nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController,
            gestureRecognizer === navigationController.interactivePopGestureRecognizer
        else {
            return false
        }

        return navigationController.viewControllers.count > 1
            && navigationController.transitionCoordinator == nil
    }
}
