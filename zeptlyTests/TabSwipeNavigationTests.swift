import CoreGraphics
import XCTest
@testable import zeptly

final class TabSwipeNavigationTests: XCTestCase {
    private let pageWidth: CGFloat = 400

    func testTabOrderingDoesNotWrap() {
        XCTAssertNil(AppTab.inbox.previous)
        XCTAssertEqual(AppTab.inbox.next, .personas)
        XCTAssertEqual(AppTab.personas.previous, .inbox)
        XCTAssertEqual(AppTab.personas.next, .settings)
        XCTAssertEqual(AppTab.settings.previous, .personas)
        XCTAssertNil(AppTab.settings.next)
    }

    func testRightEdgeSwipeLeftAdvancesOneTab() {
        XCTAssertEqual(
            destination(
                from: .inbox,
                startX: pageWidth - 10,
                translationX: -110
            ),
            .personas
        )
    }

    func testLeftEdgeSwipeRightReturnsOneTab() {
        XCTAssertEqual(
            destination(
                from: .settings,
                startX: 10,
                translationX: 110
            ),
            .personas
        )
    }

    func testSwipeStartingOutsideEdgeIsRejected() {
        XCTAssertEqual(
            destination(
                from: .inbox,
                startX: 100,
                translationX: -200
            ),
            .inbox
        )
    }

    func testVerticalDragIsRejected() {
        XCTAssertEqual(
            TabSwipeNavigation.destination(
                from: .inbox,
                startX: pageWidth - 10,
                pageWidth: pageWidth,
                translation: CGSize(width: -120, height: 110),
                predictedEndTranslation: CGSize(width: -200, height: 110)
            ),
            .inbox
        )
    }

    func testShortSlowSwipeCancels() {
        XCTAssertEqual(
            destination(
                from: .inbox,
                startX: pageWidth - 10,
                translationX: -40,
                predictedX: -60
            ),
            .inbox
        )
    }

    func testFastFlickCompletesBelowDistanceThreshold() {
        XCTAssertEqual(
            destination(
                from: .inbox,
                startX: pageWidth - 10,
                translationX: -40,
                predictedX: -180
            ),
            .personas
        )
    }

    func testCompletionDistanceCapsAt120PointsOnWideLayouts() {
        let widePageWidth: CGFloat = 1_000

        XCTAssertEqual(
            TabSwipeNavigation.destination(
                from: .inbox,
                startX: widePageWidth - 5,
                pageWidth: widePageWidth,
                translation: CGSize(width: -119, height: 0),
                predictedEndTranslation: CGSize(width: -119, height: 0)
            ),
            .inbox
        )
        XCTAssertEqual(
            TabSwipeNavigation.destination(
                from: .inbox,
                startX: widePageWidth - 5,
                pageWidth: widePageWidth,
                translation: CGSize(width: -120, height: 0),
                predictedEndTranslation: CGSize(width: -120, height: 0)
            ),
            .personas
        )
    }

    func testBoundarySwipeResistsWithoutWrapping() {
        let offset = TabSwipeNavigation.dragOffset(
            from: .inbox,
            startX: 5,
            pageWidth: pageWidth,
            translation: CGSize(width: 300, height: 0)
        )

        XCTAssertEqual(offset, TabSwipeNavigation.maximumBoundaryOffset)
        XCTAssertEqual(
            destination(
                from: .inbox,
                startX: 5,
                translationX: 300,
                predictedX: 400
            ),
            .inbox
        )
    }

    func testOppositeDirectionFromEachEdgeIsRejected() {
        XCTAssertEqual(
            destination(from: .personas, startX: 5, translationX: -150),
            .personas
        )
        XCTAssertEqual(
            destination(
                from: .personas,
                startX: pageWidth - 5,
                translationX: 150
            ),
            .personas
        )
    }

    private func destination(
        from tab: AppTab,
        startX: CGFloat,
        translationX: CGFloat,
        predictedX: CGFloat? = nil
    ) -> AppTab {
        TabSwipeNavigation.destination(
            from: tab,
            startX: startX,
            pageWidth: pageWidth,
            translation: CGSize(width: translationX, height: 0),
            predictedEndTranslation: CGSize(
                width: predictedX ?? translationX,
                height: 0
            )
        )
    }
}
