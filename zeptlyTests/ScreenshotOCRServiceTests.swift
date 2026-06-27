import UIKit
import XCTest
@testable import zeptly

final class ScreenshotOCRServiceTests: XCTestCase {
    func testReadingOrderSortsTopToBottomThenLeftToRight() {
        let lines = [
            makeLine("bottom", x: 0.1, y: 0.1),
            makeLine("right", x: 0.7, y: 0.8),
            makeLine("left", x: 0.1, y: 0.8)
        ]

        XCTAssertEqual(
            OCRDocument.readingOrder(lines).map(\.text),
            ["left", "right", "bottom"]
        )
    }

    func testModelTextContainsLayoutAndTranscript() {
        let document = OCRDocument(lines: [makeLine("Hello there", x: 0.25, y: 0.5)])

        XCTAssertTrue(document.modelText.contains("x=0.250"))
        XCTAssertTrue(document.modelText.contains("text=Hello there"))
    }

    func testVisionRecognizesRenderedText() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 400))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            NSString(string: "Hello Zeptly").draw(at: CGPoint(x: 80, y: 140), withAttributes: attributes)
        }
        let data = try XCTUnwrap(image.pngData())

        let document = try await VisionScreenshotOCRService().recognizeText(in: data)

        XCTAssertTrue(document.lines.contains { $0.text.localizedCaseInsensitiveContains("Hello") })
    }

    func testVisionRejectsInvalidImageData() async {
        do {
            _ = try await VisionScreenshotOCRService().recognizeText(in: Data("not an image".utf8))
            XCTFail("Expected invalid image error")
        } catch {
            XCTAssertEqual(error as? ScreenshotOCRError, .invalidImage)
        }
    }

    func testConfidenceThresholdCanRejectAllRecognizedText() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 240))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 240))
            NSString(string: "Visible text").draw(
                at: CGPoint(x: 60, y: 80),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 56),
                    .foregroundColor: UIColor.black
                ]
            )
        }
        let data = try XCTUnwrap(image.pngData())

        do {
            _ = try await VisionScreenshotOCRService(minimumConfidence: 1.1).recognizeText(in: data)
            XCTFail("Expected no text above the confidence threshold")
        } catch {
            XCTAssertEqual(error as? ScreenshotOCRError, .noText)
        }
    }

    private func makeLine(_ text: String, x: Double, y: Double) -> OCRLine {
        OCRLine(
            text: text,
            confidence: 0.99,
            boundingBox: OCRBoundingBox(x: x, y: y, width: 0.2, height: 0.05)
        )
    }
}
