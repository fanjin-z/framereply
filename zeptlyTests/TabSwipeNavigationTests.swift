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

    func testAcceptedEdgeSwipesNavigateOneTab() {
        let cases: [(String, AppTab, CGFloat, CGFloat, CGFloat?, CGFloat, AppTab)] = [
            ("right edge advances", .inbox, 390, -110, nil, pageWidth, .personas),
            ("left edge returns", .settings, 10, 110, nil, pageWidth, .personas),
            ("fast flick completes", .inbox, 390, -40, -180, pageWidth, .personas),
            ("wide layout caps threshold", .personas, 995, -120, -120, 1_000, .settings)
        ]

        for (name, tab, startX, translationX, predictedX, width, expected) in cases {
            XCTAssertEqual(
                destination(
                    from: tab,
                    startX: startX,
                    translationX: translationX,
                    predictedX: predictedX,
                    pageWidth: width
                ),
                expected,
                name
            )
        }
    }

    func testInvalidAndBoundarySwipesStayOnCurrentTab() {
        let cases: [(String, AppTab, CGFloat, CGSize, CGSize, CGFloat)] = [
            (
                "outside edge",
                .inbox,
                100,
                CGSize(width: -200, height: 0),
                CGSize(width: -200, height: 0),
                pageWidth
            ),
            (
                "vertical drag",
                .inbox,
                390,
                CGSize(width: -120, height: 110),
                CGSize(width: -200, height: 110),
                pageWidth
            ),
            (
                "short slow swipe",
                .inbox,
                390,
                CGSize(width: -40, height: 0),
                CGSize(width: -60, height: 0),
                pageWidth
            ),
            (
                "below capped threshold",
                .inbox,
                995,
                CGSize(width: -119, height: 0),
                CGSize(width: -119, height: 0),
                1_000
            ),
            (
                "wrong direction from left edge",
                .personas,
                5,
                CGSize(width: -150, height: 0),
                CGSize(width: -150, height: 0),
                pageWidth
            ),
            (
                "wrong direction from right edge",
                .personas,
                395,
                CGSize(width: 150, height: 0),
                CGSize(width: 150, height: 0),
                pageWidth
            ),
            (
                "boundary does not wrap",
                .inbox,
                5,
                CGSize(width: 300, height: 0),
                CGSize(width: 400, height: 0),
                pageWidth
            )
        ]

        for (name, tab, startX, translation, predicted, width) in cases {
            XCTAssertEqual(
                TabSwipeNavigation.destination(
                    from: tab,
                    startX: startX,
                    pageWidth: width,
                    translation: translation,
                    predictedEndTranslation: predicted
                ),
                tab,
                name
            )
        }

        XCTAssertEqual(
            TabSwipeNavigation.dragOffset(
                from: .inbox,
                startX: 5,
                pageWidth: pageWidth,
                translation: CGSize(width: 300, height: 0)
            ),
            TabSwipeNavigation.maximumBoundaryOffset
        )
    }

    private func destination(
        from tab: AppTab,
        startX: CGFloat,
        translationX: CGFloat,
        predictedX: CGFloat?,
        pageWidth: CGFloat
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
