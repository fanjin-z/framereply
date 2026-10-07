import Foundation

/// Measures quiet microphone audio, independently of recognition result latency.
nonisolated struct GuidanceDictationSilence {
    // Give people time to start, then allow a short thinking pause between phrases.
    static let initialTimeout: TimeInterval = 8
    static let pauseTimeout: TimeInterval = 4
    // A conservative -50 dBFS threshold avoids treating quiet speech as silence.
    static let quietThreshold = pow(10.0, -50.0 / 20.0)

    private var hasHeardAudio = false
    private var quietDuration: TimeInterval = 0
    private var hasTimedOut = false

    /// Returns true once per session, when capture should stop and finalize.
    mutating func receive(rootMeanSquare: Double?, duration: TimeInterval) -> Bool {
        guard !hasTimedOut, duration.isFinite, duration > 0 else { return false }
        guard let rootMeanSquare, rootMeanSquare.isFinite else {
            // Unknown audio formats must not be mistaken for silence.
            quietDuration = 0
            return false
        }
        if rootMeanSquare > Self.quietThreshold {
            hasHeardAudio = true
            quietDuration = 0
        } else {
            quietDuration += duration
        }
        let limit = hasHeardAudio ? Self.pauseTimeout : Self.initialTimeout
        guard quietDuration >= limit else { return false }
        hasTimedOut = true
        return true
    }
}
