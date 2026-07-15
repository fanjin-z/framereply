import XCTest

@testable import zeptly

final class SharedTranscriptInputTests: XCTestCase {
    func testMessageEstimatesCoverStandaloneCombinedAndOversizedTranscripts() {
        let standalone = SharedTranscriptInput(items: [
            "[07/13/26, 9:42 PM] Alice: Hello\ncontinued",
            "13.07.2026, 21:43 - Bob: Hi",
            "A single WeChat clipboard item"
        ])
        XCTAssertEqual(standalone.items.count, 3)
        XCTAssertEqual(standalone.characterCount, standalone.items.reduce(0) { $0 + $1.count })
        XCTAssertEqual(standalone.estimatedMessageCount, 3)

        let mixed = SharedTranscriptInput(items: [
            "[07/13/26, 9:42 PM] Alice: One\n[07/13/26, 9:43 PM] Bob: Two",
            "A standalone WeChat copied-message item"
        ])
        XCTAssertEqual(mixed.estimatedMessageCount, 3)

        let lines = (1...26).map { index in
            "[07/13/26, 9:\(String(format: "%02d", index)) PM] Alice: Message \(index)"
        }
        let oversized = SharedTranscriptInput(items: [lines.joined(separator: "\n")])
        XCTAssertEqual(oversized.estimatedMessageCount, 26)
        XCTAssertGreaterThan(
            oversized.estimatedMessageCount,
            SharedTranscriptInput.maximumEstimatedMessageCount
        )
    }
}
