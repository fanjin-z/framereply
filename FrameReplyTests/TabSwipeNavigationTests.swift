import CoreGraphics
import XCTest

@testable import FrameReply

final class TabSwipeNavigationTests: XCTestCase {
    func testEssentialTabNavigationAndBoundaries() {
        XCTAssertNil(AppTab.chats.previous)
        XCTAssertEqual(AppTab.chats.next, .personas)
        XCTAssertEqual(AppTab.personas.previous, .chats)
        XCTAssertEqual(AppTab.personas.next, .settings)
        XCTAssertEqual(AppTab.settings.previous, .personas)
        XCTAssertNil(AppTab.settings.next)
        let pageWidth: CGFloat = 400
        XCTAssertEqual(
            TabSwipeNavigation.destination(
                from: .chats, startX: 390,
                pageWidth: pageWidth,
                translation: CGSize(width: -110, height: 0),
                predictedEndTranslation: CGSize(width: -110, height: 0)
            ),
            .personas
        )
        XCTAssertEqual(
            TabSwipeNavigation.destination(
                from: .chats, startX: 5,
                pageWidth: pageWidth,
                translation: CGSize(width: 300, height: 0),
                predictedEndTranslation: CGSize(width: 400, height: 0)
            ),
            .chats
        )
    }
}
