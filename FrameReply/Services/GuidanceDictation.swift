import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class GuidanceDictation {
    enum Phase {
        case idle, preparing, downloading, listening, finishing
    }

    private(set) var phase = Phase.idle
    private(set) var text = ""
    private(set) var error: LocalizedStringResource?
    private(set) var microphoneDenied = false

    var isActive: Bool { phase != .idle }

    @ObservationIgnored private var draft: GuidanceDictationDraft?
    @ObservationIgnored private var onTextChange: ((String) -> Void)?
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var setupTask: Task<Void, Never>?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var finishTask: Task<GuidanceDictationFinalizer.Outcome, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var finalizer: GuidanceDictationFinalizer?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var continuation:
        AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeObserver: NSObjectProtocol?

    func start(
        draft: GuidanceDictationDraft, locale: Locale,
        onTextChange: @escaping (String) -> Void
    ) {
        guard !isActive else { return }
        let id = UUID()
        sessionID = id
        self.draft = draft
        self.onTextChange = onTextChange
        updateText(draft.original)
        error = nil
        microphoneDenied = false
        phase = .preparing
        setupTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard await AVAudioApplication.requestRecordPermission() else {
                    guard sessionID == id else { return }
                    microphoneDenied = true
                    fail(AppStrings.Dictation.microphoneDenied, id: id)
                    return
                }
                try checkSession(id)
                guard
                    let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale)
                else {
                    fail(AppStrings.Dictation.unavailableLanguage, id: id)
                    return
                }
                try checkSession(id)
                let transcriber = DictationTranscriber(
                    locale: supported, preset: .progressiveShortDictation)
                if let installation = try await AssetInventory.assetInstallationRequest(
                    supporting: [transcriber])
                {
                    try checkSession(id)
                    phase = .downloading
                    try await installation.downloadAndInstall()
                }
                try checkSession(id)
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                finalizer = GuidanceDictationFinalizer(
                    finalize: { try await analyzer.finalizeAndFinishThroughEndOfInput() },
                    cancel: { await analyzer.cancelAndFinishNow() })
                guard
                    let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [
                        transcriber
                    ])
                else { throw CaptureError.unavailableFormat }
                try checkSession(id)
                try await analyzer.prepareToAnalyze(in: format)
                try checkSession(id)

                let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
                self.continuation = continuation
                resultsTask = Task { [weak self] in
                    do {
                        for try await result in transcriber.results {
                            guard let self, self.sessionID == id, !Task.isCancelled else { return }
                            self.draft?.receive(
                                String(result.text.characters), isFinal: result.isFinal)
                            self.updateText(self.draft?.text ?? self.text)
                            if !DraftingInputLimits.canAccept(self.text), self.phase == .listening {
                                self.stop()
                            }
                        }
                        // Short dictation can finish itself (for example after silence).
                        if let self, self.sessionID == id, self.phase == .listening {
                            self.stop()
                        }
                    } catch {
                        self?.fail(AppStrings.Dictation.failed, id: id)
                    }
                }
                try await analyzer.start(inputSequence: stream)
                try checkSession(id)
                try await startCapture(format: format, continuation: continuation, id: id)
                phase = .listening
                observeInterruptions(id: id)
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled, self?.sessionID == id else { return }
                    self?.stop()
                }
            } catch is CancellationError {
                // Cancellation already released the session and preserved the draft.
            } catch {
                fail(AppStrings.Dictation.failed, id: id)
            }
        }
    }

    /// Stops capture immediately; callers can await the shared task for the final text.
    @discardableResult
    func stop() -> Task<GuidanceDictationFinalizer.Outcome, Never>? {
        guard let id = sessionID, isActive else { return nil }
        if phase == .finishing { return finishTask }
        guard phase == .listening, let finalizer else {
            cancel()
            return nil
        }
        phase = .finishing
        let audioCleanup = stopCapture()
        continuation?.finish()
        continuation = nil
        timeoutTask?.cancel()
        let resultsTask = resultsTask
        finishTask = Task { [weak self] in
            let outcome = await finalizer.finish { [weak self] in
                await resultsTask?.value
                await audioCleanup?.value
                return self?.text ?? ""
            }
            guard let self, self.sessionID == id else { return .cancelled }
            if outcome == .failed { self.error = AppStrings.Dictation.failed }
            self.releaseSession()
            return outcome
        }
        return finishTask
    }

    /// Used on dismissal/backgrounding. Late results cannot overwrite subsequent edits.
    func cancel(discard: Bool = false) {
        if discard, let draft { updateText(draft.original) }
        releaseSession()
    }

    private func updateText(_ value: String) {
        text = value
        onTextChange?(value)
    }

    private func checkSession(_ id: UUID) throws {
        try Task.checkCancellation()
        guard sessionID == id else { throw CancellationError() }
    }

    private func fail(_ message: LocalizedStringResource, id: UUID) {
        guard sessionID == id else { return }
        error = message
        finalizer?.cancel(with: .failed)
        releaseSession()
    }

    private func startCapture(
        format: AVAudioFormat,
        continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
        id: UUID
    ) async throws {
        try await GuidanceDictationAudioSession.shared.activate(for: id).value
        try checkSession(id)
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
            let converter = DictationAudioConverter(from: inputFormat, to: format)
        else { throw CaptureError.unavailableFormat }
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            do {
                if let converted = try converter.convert(buffer) {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
                if converter.shouldStopAfterSilence(in: buffer) {
                    Task { @MainActor [weak self] in
                        guard let self, self.sessionID == id, self.phase == .listening else {
                            return
                        }
                        self.stop()
                    }
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
        self.engine = engine
        engine.prepare()
        try engine.start()
    }

    private func observeInterruptions(id: UUID) {
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard
                notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                    == AVAudioSession.InterruptionType.began.rawValue
            else { return }
            Task { @MainActor [weak self] in
                guard self?.sessionID == id else { return }
                self?.stop()
            }
        }
        routeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard
                let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
                reason == .oldDeviceUnavailable || reason == .newDeviceAvailable
                    || reason == .noSuitableRouteForCategory
            else { return }
            Task { @MainActor [weak self] in
                guard self?.sessionID == id else { return }
                self?.stop()
            }
        }
    }

    @discardableResult
    private func stopCapture() -> Task<Void, Never>? {
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            self.engine = nil
        }
        for observer in [interruptionObserver, routeObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        interruptionObserver = nil
        routeObserver = nil
        return sessionID.map { GuidanceDictationAudioSession.shared.deactivate(for: $0) }
    }

    private func releaseSession() {
        stopCapture()
        sessionID = nil
        continuation?.finish()
        continuation = nil
        setupTask?.cancel()
        resultsTask?.cancel()
        finishTask?.cancel()
        timeoutTask?.cancel()
        setupTask = nil
        resultsTask = nil
        finishTask = nil
        timeoutTask = nil
        finalizer?.cancel()
        finalizer = nil
        draft = nil
        onTextChange = nil
        phase = .idle
    }
}

nonisolated private enum CaptureError: Error {
    case unavailableFormat, conversionFailed
}

/// Only accessed by the audio engine's serial tap callback. Each yielded buffer
/// is separately allocated; the engine's reusable input buffer never escapes.
nonisolated private final class DictationAudioConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private var silence = GuidanceDictationSilence()

    init?(from input: AVAudioFormat, to output: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: input, to: output) else { return nil }
        self.converter = converter
        format = output
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        let capacity =
            AVAudioFrameCount(
                ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw CaptureError.conversionFailed
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard status != .error else { throw CaptureError.conversionFailed }
        return output.frameLength > 0 ? output : nil
    }

    func shouldStopAfterSilence(in input: AVAudioPCMBuffer) -> Bool {
        silence.receive(
            rootMeanSquare: rootMeanSquare(in: input),
            duration: Double(input.frameLength) / input.format.sampleRate)
    }

    private func rootMeanSquare(in input: AVAudioPCMBuffer) -> Double? {
        guard input.frameLength > 0, input.format.channelCount > 0 else { return nil }
        func level<Sample>(
            _ channels: UnsafePointer<UnsafeMutablePointer<Sample>>,
            normalize: (Sample) -> Double
        ) -> Double {
            var loudest: Double = 0
            for channel in 0..<Int(input.format.channelCount) {
                var sum: Double = 0
                for frame in 0..<Int(input.frameLength) {
                    let sample = normalize(channels[channel][frame * input.stride])
                    sum += sample * sample
                }
                loudest = max(loudest, sqrt(sum / Double(input.frameLength)))
            }
            return loudest
        }
        if let channels = input.floatChannelData {
            return level(channels) { Double($0) }
        }
        if let channels = input.int16ChannelData {
            return level(channels) { Double($0) / 32768 }
        }
        if let channels = input.int32ChannelData {
            return level(channels) { Double($0) / 2_147_483_648 }
        }
        return nil
    }
}
