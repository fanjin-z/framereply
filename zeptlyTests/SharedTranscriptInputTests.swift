import XCTest

@testable import zeptly

final class SharedTranscriptInputTests: XCTestCase {
    func testMessageEstimatesCoverStandaloneAndGeneratedCombinedTranscripts() {
        let standalone = SharedTranscriptInput(items: [
            "[07/13/26, 9:42 PM] Alice: Hello\ncontinued",
            "13.07.2026, 21:43 - Bob: Hi",
            "A single WeChat clipboard item"
        ])
        XCTAssertEqual(standalone.items.count, 3)
        XCTAssertEqual(standalone.characterCount, standalone.items.reduce(0) { $0 + $1.count })
        XCTAssertEqual(standalone.estimatedMessageCount, 3)

        let generatedTranscript = (1...9).map { index in
            let sender = index.isMultiple(of: 2) ? "Person A" : "Person B"
            let minute = String(format: "%02d", index)
            return "[07/13/26, 9:\(minute) PM] \(sender): Test message \(index)"
        }
        .joined(separator: "\n\n")
        let combined = SharedTranscriptInput(items: [generatedTranscript])

        XCTAssertEqual(combined.items, [generatedTranscript])
        XCTAssertEqual(combined.estimatedMessageCount, 9)
        XCTAssertEqual(combined.characterCount, generatedTranscript.count)
    }
}
