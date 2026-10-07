import XCTest

@testable import FrameReply

final class GuidanceDictationSilenceTests: XCTestCase {
    func testInitialSilenceAllowsTimeToBeginSpeaking() {
        var silence = GuidanceDictationSilence()
        XCTAssertFalse(silence.receive(rootMeanSquare: 0, duration: 7.5))
        XCTAssertTrue(silence.receive(rootMeanSquare: 0, duration: 0.5))
        XCTAssertFalse(silence.receive(rootMeanSquare: 0, duration: 8))
    }

    func testResumingSpeechResetsTheFourSecondPause() {
        var silence = GuidanceDictationSilence()
        XCTAssertFalse(silence.receive(rootMeanSquare: 0.1, duration: 1))
        XCTAssertFalse(silence.receive(rootMeanSquare: 0, duration: 3.5))
        XCTAssertFalse(silence.receive(rootMeanSquare: 0.1, duration: 1))
        XCTAssertFalse(silence.receive(rootMeanSquare: 0, duration: 3.5))
        XCTAssertTrue(silence.receive(rootMeanSquare: 0, duration: 0.5))
    }

    func testQuietSpeechAndUnknownAudioAreNotTreatedAsSilence() {
        var silence = GuidanceDictationSilence()
        // -46 dBFS: quiet but audible input must keep capture alive, even if the
        // recognizer has not produced any text yet.
        XCTAssertFalse(silence.receive(rootMeanSquare: 0.005, duration: 9))
        XCTAssertFalse(silence.receive(rootMeanSquare: 0, duration: 3.5))
        XCTAssertFalse(silence.receive(rootMeanSquare: nil, duration: 1))
        XCTAssertFalse(silence.receive(rootMeanSquare: 0, duration: 3.5))
        XCTAssertTrue(silence.receive(rootMeanSquare: 0, duration: 0.5))
    }
}
