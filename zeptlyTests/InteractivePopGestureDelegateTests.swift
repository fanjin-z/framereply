import SwiftUI
import UIKit
import XCTest
@testable import zeptly

@MainActor
final class InteractivePopGestureDelegateTests: XCTestCase {
    func testRejectsPopGestureAtNavigationRoot() throws {
        let navigationController = makeNavigationController()
        let delegate = InteractivePopGestureDelegate()
        let gestureRecognizer = try XCTUnwrap(
            navigationController.interactivePopGestureRecognizer
        )

        delegate.install(on: navigationController)

        XCTAssertFalse(delegate.gestureRecognizerShouldBegin(gestureRecognizer))
    }

    func testAllowsPopGestureWhenPreviousScreenExists() throws {
        let navigationController = makeNavigationController()
        navigationController.pushViewController(UIViewController(), animated: false)
        let delegate = InteractivePopGestureDelegate()
        let gestureRecognizer = try XCTUnwrap(
            navigationController.interactivePopGestureRecognizer
        )

        delegate.install(on: navigationController)

        XCTAssertTrue(delegate.gestureRecognizerShouldBegin(gestureRecognizer))
    }

    func testRestoresPreviousGestureDelegate() throws {
        let navigationController = makeNavigationController()
        let gestureRecognizer = try XCTUnwrap(
            navigationController.interactivePopGestureRecognizer
        )
        let originalDelegate = GestureDelegateStub()
        let delegate = InteractivePopGestureDelegate()
        gestureRecognizer.delegate = originalDelegate

        delegate.install(on: navigationController)
        XCTAssertTrue(gestureRecognizer.delegate === delegate)

        delegate.restorePreviousDelegate()
        XCTAssertTrue(gestureRecognizer.delegate === originalDelegate)
    }

    func testModifierInstallsDelegateInSwiftUINavigationStack() async throws {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let hostingController = UIHostingController(rootView: SwipeBackNavigationFixture())
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let navigationController = try XCTUnwrap(
            findNavigationController(in: hostingController)
        )
        let gestureRecognizer = try XCTUnwrap(
            navigationController.interactivePopGestureRecognizer
        )

        XCTAssertGreaterThan(navigationController.viewControllers.count, 1)
        XCTAssertTrue(gestureRecognizer.delegate is InteractivePopGestureDelegate)
    }

    private func makeNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(
            rootViewController: UIViewController()
        )
        navigationController.loadViewIfNeeded()
        return navigationController
    }

    private func findNavigationController(
        in viewController: UIViewController
    ) -> UINavigationController? {
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }

        for child in viewController.children {
            if let navigationController = findNavigationController(in: child) {
                return navigationController
            }
        }

        return nil
    }
}

private final class GestureDelegateStub: NSObject, UIGestureRecognizerDelegate {}

private struct SwipeBackNavigationFixture: View {
    @State private var path = [1]

    var body: some View {
        NavigationStack(path: $path) {
            Color.clear
                .navigationDestination(for: Int.self) { _ in
                    Color.clear
                        .interactiveSwipeBackEnabled()
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
    }
}
