import UIKit
import XCTest

@testable import zeptly

@MainActor
final class InteractivePopGestureDelegateTests: XCTestCase {
    func testDelegateGatesAndRestoresInteractivePopGesture() throws {
        let navigationController = UINavigationController(
            rootViewController: UIViewController()
        )
        navigationController.loadViewIfNeeded()
        let gestureRecognizer = try XCTUnwrap(
            navigationController.interactivePopGestureRecognizer
        )
        let originalDelegate = GestureDelegateStub()
        let delegate = InteractivePopGestureDelegate()
        gestureRecognizer.delegate = originalDelegate

        delegate.install(on: navigationController)

        XCTAssertTrue(gestureRecognizer.delegate === delegate)
        XCTAssertFalse(delegate.gestureRecognizerShouldBegin(gestureRecognizer))

        navigationController.pushViewController(UIViewController(), animated: false)
        XCTAssertTrue(delegate.gestureRecognizerShouldBegin(gestureRecognizer))

        delegate.restorePreviousDelegate()
        XCTAssertTrue(gestureRecognizer.delegate === originalDelegate)
    }
}

private final class GestureDelegateStub: NSObject, UIGestureRecognizerDelegate {}
