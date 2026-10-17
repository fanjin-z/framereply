import AVFoundation

/// Orders activation and cleanup across both guidance editors, including cancelled setup.
@MainActor
final class GuidanceDictationAudioSession {
    static let shared = GuidanceDictationAudioSession()

    private let activateSession: () async throws -> Void
    private let deactivateSession: () async throws -> Void
    private var tail: Task<Void, Never>?
    private var owner: UUID?
    nonisolated private static let legacyQueue = DispatchQueue(
        label: "com.framereply.guidance-audio-session")

    init(
        activate: (() async throws -> Void)? = nil,
        deactivate: (() async throws -> Void)? = nil
    ) {
        activateSession = activate ?? Self.activateSystemSession
        deactivateSession = deactivate ?? Self.deactivateSystemSession
    }

    func activate(for id: UUID) -> Task<Void, Error> {
        let previous = tail
        let task = Task {
            await previous?.value
            guard owner == nil else { throw SessionError.inUse }
            try await activateSession()
            owner = id
        }
        tail = Task { _ = try? await task.value }
        return task
    }

    @discardableResult
    func deactivate(for id: UUID) -> Task<Void, Never> {
        let previous = tail
        let task = Task {
            await previous?.value
            guard owner == id else { return }
            try? await deactivateSession()
            owner = nil
        }
        tail = task
        return task
    }

    private static func activateSystemSession() async throws {
        try await onLegacyQueue {
            try AVAudioSession.sharedInstance().setCategory(
                .record, mode: .measurement, options: [.allowBluetoothHFP])
        }
        if #available(iOS 27.0, *) {
            guard try await AVAudioSession.sharedInstance().activate(options: []) else {
                throw SessionError.activationFailed
            }
        } else {
            try await onLegacyQueue { try AVAudioSession.sharedInstance().setActive(true) }
        }
    }

    private static func deactivateSystemSession() async throws {
        if #available(iOS 27.0, *) {
            guard
                try await AVAudioSession.sharedInstance().deactivate(
                    options: .notifyOthersOnDeactivation)
            else { throw SessionError.deactivationFailed }
        } else {
            try await onLegacyQueue {
                try AVAudioSession.sharedInstance().setActive(
                    false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    private static func onLegacyQueue(_ operation: @escaping @Sendable () throws -> Void)
        async throws
    {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            legacyQueue.async {
                do {
                    try operation()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private enum SessionError: Error {
        case inUse, activationFailed, deactivationFailed
    }
}
