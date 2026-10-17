import XCTest

@testable import FrameReply

@MainActor
final class GuidanceDictationLifecycleTests: XCTestCase {
    func testOverlappingStopsWaitForFinalResultsAndDoNotCancelFinishedAnalyzer() async {
        let finalizing = expectation(description: "Finalization started")
        let reading = expectation(description: "Reading remaining results")
        let finalizeGate = Gate()
        let resultsGate = Gate()
        var finalizeCount = 0
        let cancelled = expectation(description: "Finished analyzer must not be cancelled")
        cancelled.isInverted = true
        var text = "Keep it"
        let finalizer = GuidanceDictationFinalizer(
            finalize: {
                finalizeCount += 1
                finalizing.fulfill()
                await finalizeGate.wait()
            },
            cancel: { cancelled.fulfill() })
        let first = Task {
            await finalizer.finish {
                reading.fulfill()
                await resultsGate.wait()
                return text
            }
        }
        await fulfillment(of: [finalizing], timeout: 1)
        let secondStarted = expectation(description: "Second stop requested")
        let second = Task {
            secondStarted.fulfill()
            return await finalizer.finish {
                XCTFail("Only the first stop may drain results")
                return ""
            }
        }
        await fulfillment(of: [secondStarted], timeout: 1)
        finalizeGate.open()
        await fulfillment(of: [reading], timeout: 1)
        text = "Keep it short and friendly."
        resultsGate.open()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, .finished(text))
        XCTAssertEqual(secondResult, firstResult)
        finalizer.cancel()
        finalizer.cancel()
        XCTAssertEqual(finalizeCount, 1)
        await fulfillment(of: [cancelled], timeout: 0.05)
    }

    func testCancellationUnblocksSubmissionAndRejectsLateFinalText() async {
        let finalizing = expectation(description: "Finalization started")
        let cancelled = expectation(description: "Analyzer cancelled once")
        let gate = Gate()
        let readFinalText = expectation(description: "Cancelled session must not publish late text")
        readFinalText.isInverted = true
        let finalizer = GuidanceDictationFinalizer(
            finalize: {
                finalizing.fulfill()
                await gate.wait()
            },
            cancel: { cancelled.fulfill() })
        let submission = Task {
            await finalizer.finish {
                readFinalText.fulfill()
                return "Must not submit"
            }
        }
        await fulfillment(of: [finalizing], timeout: 1)
        finalizer.cancel()
        finalizer.cancel()
        let outcome = await submission.value
        XCTAssertEqual(outcome, .cancelled)
        await fulfillment(of: [cancelled], timeout: 1)
        gate.open()
        let laterOutcome = await finalizer.finish { "Newer draft" }
        XCTAssertEqual(laterOutcome, .cancelled)
        await fulfillment(of: [readFinalText], timeout: 0.05)
    }

    func testCancellationWhileDrainingResultsDoesNotCancelFinishedAnalyzer() async {
        let reading = expectation(description: "Analyzer finished, results pending")
        let gate = Gate()
        let cancelled = expectation(description: "Finished analyzer must not be cancelled")
        cancelled.isInverted = true
        let finalizer = GuidanceDictationFinalizer(
            finalize: {}, cancel: { cancelled.fulfill() })
        let submission = Task {
            await finalizer.finish {
                reading.fulfill()
                await gate.wait()
                return "Late text"
            }
        }
        await fulfillment(of: [reading], timeout: 1)
        finalizer.cancel()
        let outcome = await submission.value
        XCTAssertEqual(outcome, .cancelled)
        gate.open()
        await fulfillment(of: [cancelled], timeout: 0.05)
    }

    func testStuckFinalizationTimesOutWithoutSubmittingPartialText() async {
        let cancelled = expectation(description: "Timed out analyzer cancelled")
        let gate = Gate()
        let finalizer = GuidanceDictationFinalizer(
            timeout: .milliseconds(20),
            finalize: { await gate.wait() },
            cancel: { cancelled.fulfill() })
        let outcome = await finalizer.finish {
            XCTFail("Timed out dictation must not submit partial text")
            return "Partial text"
        }
        XCTAssertEqual(outcome, .failed)
        await fulfillment(of: [cancelled], timeout: 1)
        gate.open()
    }

    func testCancelledActivationIsCleanedUpBeforeRestartAndStaleCleanupIsIgnored() async throws {
        let activating = expectation(description: "First activation pending")
        let gate = Gate()
        var events: [String] = []
        var activationCount = 0
        let audio = GuidanceDictationAudioSession(
            activate: {
                activationCount += 1
                events.append("activate \(activationCount)")
                if activationCount == 1 {
                    activating.fulfill()
                    await gate.wait()
                }
            },
            deactivate: { events.append("deactivate") })
        let firstID = UUID()
        let secondID = UUID()
        let first = audio.activate(for: firstID)
        await fulfillment(of: [activating], timeout: 1)
        audio.deactivate(for: firstID)
        let second = audio.activate(for: secondID)
        let staleCleanup = audio.deactivate(for: firstID)
        XCTAssertEqual(events, ["activate 1"])
        gate.open()
        try await first.value
        try await second.value
        await staleCleanup.value
        XCTAssertEqual(events, ["activate 1", "deactivate", "activate 2"])
        await audio.deactivate(for: secondID).value
        XCTAssertEqual(events, ["activate 1", "deactivate", "activate 2", "deactivate"])
    }

    private final class Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            let waiters = waiters
            self.waiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }
}
