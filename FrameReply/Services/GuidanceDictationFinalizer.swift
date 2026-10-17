import Foundation

/// One terminal outcome per recording, shared by manual stop, silence, and submission.
@MainActor
final class GuidanceDictationFinalizer {
    enum Outcome: Equatable {
        case finished(String)
        case cancelled, failed
    }

    private let finalize: () async throws -> Void
    private let cancelAnalyzer: () async -> Void
    private let timeout: Duration
    private var task: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var didFinalize = false
    private var outcome: Outcome?
    private var waiters: [CheckedContinuation<Outcome, Never>] = []

    init(
        timeout: Duration = .seconds(5),
        finalize: @escaping () async throws -> Void,
        cancel: @escaping () async -> Void
    ) {
        self.timeout = timeout
        self.finalize = finalize
        cancelAnalyzer = cancel
    }

    func finish(readFinalText: @escaping () async -> String) async -> Outcome {
        if let outcome { return outcome }
        if task == nil {
            task = Task {
                do {
                    try await finalize()
                    didFinalize = true
                    guard outcome == nil else { return }
                    let text = await readFinalText()
                    resolve(.finished(text))
                } catch {
                    cancel(with: .failed)
                }
            }
            timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                cancel(with: .failed)
            }
        }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func cancel(with outcome: Outcome = .cancelled) {
        guard self.outcome == nil else { return }
        task?.cancel()
        if !didFinalize {
            let cancelAnalyzer = cancelAnalyzer
            Task { await cancelAnalyzer() }
        }
        resolve(outcome)
    }

    private func resolve(_ outcome: Outcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        timeoutTask?.cancel()
        timeoutTask = nil
        task = nil
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters { waiter.resume(returning: outcome) }
    }
}
