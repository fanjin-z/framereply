import CoreGraphics
import XCTest

@testable import FrameReply

final class TabSwipeNavigationTests: XCTestCase {
    func testEssentialTabNavigationAndBoundaries() {
        XCTAssertNil(AppTab.inbox.previous)
        XCTAssertEqual(AppTab.inbox.next, .personas)
        XCTAssertEqual(AppTab.personas.previous, .inbox)
        XCTAssertEqual(AppTab.personas.next, .settings)
        XCTAssertEqual(AppTab.settings.previous, .personas)
        XCTAssertNil(AppTab.settings.next)
        let pageWidth: CGFloat = 400
        XCTAssertEqual(
            TabSwipeNavigation.destination(
                from: .inbox, startX: 390,
                pageWidth: pageWidth,
                translation: CGSize(width: -110, height: 0),
                predictedEndTranslation: CGSize(width: -110, height: 0)
            ),
            .personas
        )
        XCTAssertEqual(
            TabSwipeNavigation.destination(
                from: .inbox, startX: 5,
                pageWidth: pageWidth,
                translation: CGSize(width: 300, height: 0),
                predictedEndTranslation: CGSize(width: 400, height: 0)
            ),
            .inbox
        )
    }
}
