import CryptoKit
import DeviceCheck
import Foundation
import Security

nonisolated enum AppAttestOperation: String {
    case status, subscription

    var path: String {
        switch self {
        case .status: "/v1/auth/status"
        case .subscription: "/v1/subscriptions/verify"
        }
    }
}

@MainActor
protocol AppAttestAuthenticating {
    func post(operation: AppAttestOperation, body: Data) async throws -> Data
}

nonisolated enum AppAttestClientError: Error, LocalizedError, Equatable {
    case invalidConfiguration, unsupported, invalidResponse, network, storage
    case appleUnavailable, appleInvalidKey
    case appleFailure(code: Int)
    case enrollmentExpired, enrollmentUncertain, recoveryRequired
    case backend(status: Int, code: String?)

    var errorDescription: String? { diagnosticSummary }

    var diagnosticSummary: String {
        switch self {
        case .invalidConfiguration:
            "App Attest configuration is invalid. Check the HTTPS backend URL and signed app environment."
        case .unsupported:
            "App Attest requires a supported physical iPhone or iPad. Simulator and Mac authentication are unavailable."
        case .invalidResponse:
            "The authentication response was malformed. Check the backend deployment."
        case .network:
            "The authentication request could not complete. Check connectivity and retry."
        case .storage:
            "The device authentication state could not be saved or read. Unlock the device and retry."
        case .appleUnavailable:
            "Apple App Attest is temporarily unavailable. Retry later; the existing key and challenge are retained."
        case .appleInvalidKey, .recoveryRequired:
            "Apple could not use the device key after bounded recovery. Check App Attest signing and device support before retrying."
        case .appleFailure(let code):
            "Apple App Attest failed (code \(code)). Check the app's capability and signing configuration."
        case .enrollmentExpired:
            "Enrollment expired before registration. Retry to complete device authentication."
        case .enrollmentUncertain:
            "Enrollment could not be confirmed and its challenge expired. Check the backend device record; the key was retained to avoid replacing a disabled identity."
        case .backend(let status, let code):
            switch code {
            case "INVALID_TRANSACTION":
                "Apple transaction rejected (HTTP \(status)). Check the Sandbox product and bundle configuration, then use Recheck purchase."
            case "SUBSCRIPTION_UNAVAILABLE":
                "Apple verification unavailable (HTTP \(status)). Check the Sandbox Apple secret and backend logs, then use Recheck purchase."
            case "NOT_FOUND":
                "Backend route missing (HTTP \(status)). Deploy Step 4A and check the API URL."
            default:
                status == 404
                    ? "Backend route missing (HTTP 404). Deploy Step 4A and check the API URL."
                    : "Backend authentication returned HTTP \(status)\(code.map { " (\($0))" } ?? ""). Check the backend environment and device registration."
            }
        }
    }
}

@MainActor
protocol AppAttestServicing {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

@MainActor
final class AppAttestClient: AppAttestAuthenticating {
    private static var clients: [String: AppAttestClient] = [:]

    /// Sharing also serializes counters across separately constructed screens/clients.
    static func shared(baseURL: URL, environment: String) -> AppAttestClient {
        let key = namespace(baseURL: baseURL, environment: environment)
        if let client = clients[key] { return client }
        let client = AppAttestClient(baseURL: baseURL, environment: environment)
        clients[key] = client
        return client
    }

    private let baseURL: URL?
    private let environment: String
    private let session: URLSession
    private let service: any AppAttestServicing
    private let storage: any KeychainStoring
    private let account: String
    private let now: () -> Date
    private var busy = false
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []
    private var unsavedState: Enrollment?

    init(
        baseURL: URL,
        environment: String,
        session: URLSession = ProviderNetworkSession.make(),
        service: (any AppAttestServicing)? = nil,
        storage: (any KeychainStoring)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.baseURL = Self.cleanBaseURL(baseURL)
        self.environment = environment
        self.session = session
        self.service = service ?? SystemAppAttestService()
        self.storage = storage ?? AppAttestKeychainStore()
        self.account = Self.namespace(baseURL: baseURL, environment: environment)
        self.now = now
    }

    func post(operation: AppAttestOperation, body: Data) async throws -> Data {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        guard baseURL != nil, ["development", "production"].contains(environment) else {
            throw AppAttestClientError.invalidConfiguration
        }
        guard service.isSupported else { throw AppAttestClientError.unsupported }
        guard !body.isEmpty, body.count <= 32 * 1_024 else {
            throw AppAttestClientError.invalidResponse
        }

        var state = try load() ?? Enrollment()
        // One automatic replacement is allowed until successful enrollment. A bad signing
        // configuration must not create another Apple key on every tap or app launch.
        for attempt in 0..<2 {
            do {
                if state.keyID == nil { try await createKey(state: &state) }
                try await enroll(state: &state)
                return try await authenticated(operation: operation, body: body, state: state)
            } catch AppAttestClientError.appleInvalidKey {
                guard attempt == 0, !state.replacementUsed else {
                    throw AppAttestClientError.recoveryRequired
                }
                state = Enrollment(replacementUsed: true)
                try save(state)
            } catch let failure as EnrollmentFailure {
                guard attempt == 0, !state.replacementUsed else { throw failure.cause }
                state = Enrollment(replacementUsed: true)
                try save(state)
            } catch AppAttestClientError.enrollmentExpired {
                guard attempt == 0, !state.replacementUsed else {
                    throw AppAttestClientError.recoveryRequired
                }
                state = Enrollment(replacementUsed: true)
                try save(state)
            }
        }
        throw AppAttestClientError.recoveryRequired
    }

    private struct Challenge: Codable {
        let challengeId: String
        let clientData: String
        let expiresAt: String

        var bytes: Data? {
            guard let data = Data(base64Encoded: clientData), !data.isEmpty,
                data.count <= 4_096, data.base64EncodedString() == clientData
            else { return nil }
            return data
        }

        var expiration: Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: expiresAt)
                ?? ISO8601DateFormatter().date(from: expiresAt)
        }
    }

    private struct Pending: Codable {
        let challenge: Challenge
        var attestation: Data?
        var started = false
        var submitted = false
    }

    private struct EnrollmentFailure: Error { let cause: AppAttestClientError }

    private struct Enrollment: Codable {
        var version = 1
        var keyID: String?
        var registered = false
        var pending: Pending?
        var replacementUsed = false
    }

    private func createKey(state: inout Enrollment) async throws {
        let key = try await service.generateKey()
        guard Self.validKey(key) else { throw AppAttestClientError.invalidResponse }
        state.keyID = key
        // Persist even if cancellation arrived while the framework was creating the key.
        try save(state)
        try Task.checkCancellation()
    }

    private func enroll(state: inout Enrollment) async throws {
        guard !state.registered, let keyID = state.keyID else { return }
        if let pending = state.pending, pending.submitted {
            do {
                let data = try await authenticated(
                    operation: .status, body: Data("{}".utf8), state: state)
                struct Status: Decodable { let authenticated: Bool }
                guard (try? JSONDecoder().decode(Status.self, from: data).authenticated) == true
                else {
                    throw AppAttestClientError.invalidResponse
                }
                try markRegistered(state: &state)
                return
            } catch AppAttestClientError.backend(let status, _) where status == 401 {
                // An unknown and a disabled device deliberately have the same server error.
                // Only retry this pending proof; never create a new identity from HTTP 401.
                guard let expiration = pending.challenge.expiration, expiration > now() else {
                    throw AppAttestClientError.enrollmentUncertain
                }
            }
        }
        if state.pending == nil
            || (state.pending?.started == false
                && (state.pending?.challenge.expiration ?? .distantPast) <= now())
        {
            let challenge = try await challenge(keyID: keyID, operation: "attest", body: nil)
            state.pending = Pending(challenge: challenge)
            try save(state)
        }
        guard var pending = state.pending, let bytes = pending.challenge.bytes else {
            throw AppAttestClientError.storage
        }
        if pending.attestation == nil {
            // serverUnavailable must retry these exact inputs, even across app launches.
            // Once Apple signs a key it cannot be attested again with a different challenge.
            try Task.checkCancellation()
            pending.started = true
            state.pending = pending
            try save(state)
            let proof: Data
            do {
                proof = try await service.attestKey(keyID, clientDataHash: Self.hash(bytes))
            } catch let error as AppAttestClientError {
                switch error {
                case .appleInvalidKey, .appleFailure:
                    // Apple prescribes a new key after non-transient attestation failures.
                    // This is bounded above; assertion/backend failures use separate rules.
                    throw EnrollmentFailure(cause: error)
                default: throw error
                }
            }
            guard !proof.isEmpty, proof.count <= 64 * 1_024 else {
                throw AppAttestClientError.invalidResponse
            }
            pending.attestation = proof
            state.pending = pending
            try save(state)
        }
        try Task.checkCancellation()
        guard let expiration = pending.challenge.expiration, expiration > now() else {
            // No request left the device, so a bounded replacement cannot bypass a disabled key.
            throw pending.submitted
                ? AppAttestClientError.enrollmentUncertain : AppAttestClientError.enrollmentExpired
        }
        pending.submitted = true
        state.pending = pending
        try save(state)
        struct AttestationBody: Encodable {
            let keyId: String
            let challengeId: String
            let attestation: String
        }
        let body = try JSONEncoder().encode(
            AttestationBody(
                keyId: keyID, challengeId: pending.challenge.challengeId,
                attestation: pending.attestation!.base64EncodedString()))
        let data = try await send(path: "/v1/auth/attest", body: body)
        struct Registration: Decodable { let registered: Bool }
        guard (try? JSONDecoder().decode(Registration.self, from: data).registered) == true else {
            throw AppAttestClientError.invalidResponse
        }
        try markRegistered(state: &state)
    }

    private func markRegistered(state: inout Enrollment) throws {
        state.registered = true
        state.pending = nil
        state.replacementUsed = false
        try save(state)
    }

    private func authenticated(operation: AppAttestOperation, body: Data, state: Enrollment)
        async throws -> Data
    {
        guard let keyID = state.keyID else { throw AppAttestClientError.storage }
        let challenge = try await challenge(keyID: keyID, operation: operation.rawValue, body: body)
        guard let bytes = challenge.bytes else { throw AppAttestClientError.invalidResponse }
        let assertion = try await service.generateAssertion(keyID, clientDataHash: Self.hash(bytes))
        guard !assertion.isEmpty, assertion.count <= 16 * 1_024 else {
            throw AppAttestClientError.invalidResponse
        }
        // Never cache or replay an assertion, including when a later subscription phase fails.
        return try await send(
            path: operation.path, body: body,
            headers: [
                "X-App-Attest-Key-Id": keyID,
                "X-App-Attest-Challenge-Id": challenge.challengeId,
                "X-App-Attest-Assertion": assertion.base64EncodedString()
            ])
    }

    private func challenge(keyID: String, operation: String, body: Data?) async throws -> Challenge
    {
        struct Body: Encodable {
            let keyId: String
            let operation: String
            let bodyHash: String?
        }
        let data = try await send(
            path: "/v1/auth/challenges",
            body: JSONEncoder().encode(
                Body(
                    keyId: keyID, operation: operation, bodyHash: body.map(Self.hexHash))))
        guard let challenge = try? JSONDecoder().decode(Challenge.self, from: data),
            UUID(uuidString: challenge.challengeId) != nil,
            challenge.bytes != nil, let expiration = challenge.expiration, expiration > now()
        else { throw AppAttestClientError.invalidResponse }
        return challenge
    }

    private func send(path: String, body: Data, headers: [String: String] = [:]) async throws
        -> Data
    {
        try Task.checkCancellation()
        guard let baseURL else { throw AppAttestClientError.invalidConfiguration }
        var request = URLRequest(url: baseURL.appending(path: String(path.dropFirst())))
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(
                for: request, delegate: RejectAppAttestRedirects())
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw AppAttestClientError.network
        }
        guard let http = response as? HTTPURLResponse, http.url == request.url,
            data.count <= 128 * 1_024
        else { throw AppAttestClientError.invalidResponse }
        guard http.statusCode == 200 else {
            struct Failure: Decodable {
                struct Detail: Decodable { let code: String }
                let error: Detail
            }
            let code = try? JSONDecoder().decode(Failure.self, from: data).error.code
            let allowed = [
                "NOT_FOUND", "INTERNAL_ERROR", "INVALID_REQUEST", "INVALID_TRANSACTION",
                "SUBSCRIPTION_UNAVAILABLE", "INVALID_AUTH_REQUEST", "UNAUTHENTICATED",
                "AUTH_UNAVAILABLE"
            ]
            throw AppAttestClientError.backend(
                status: http.statusCode, code: code.flatMap { allowed.contains($0) ? $0 : nil })
        }
        return data
    }

    private func load() throws -> Enrollment? {
        do {
            if let state = unsavedState {
                try save(state)
                return state
            }
            guard let value = try storage.get(account: account) else { return nil }
            let state = try JSONDecoder().decode(Enrollment.self, from: Data(value.utf8))
            guard state.version == 1, state.keyID.map(Self.validKey) ?? !state.registered,
                state.pending == nil || (state.keyID != nil && !state.registered),
                state.pending?.challenge.bytes != nil || state.pending == nil
            else { throw AppAttestClientError.storage }
            return state
        } catch { throw AppAttestClientError.storage }
    }

    private func save(_ state: Enrollment) throws {
        do {
            let data = try JSONEncoder().encode(state)
            try storage.set(String(decoding: data, as: UTF8.self), for: account)
            unsavedState = nil
        } catch {
            // Keep a newly generated identifier in this process if Keychain is unavailable.
            // The next attempt must persist it before continuing, rather than creating keys.
            unsavedState = state
            throw AppAttestClientError.storage
        }
    }

    private static func validKey(_ value: String) -> Bool {
        guard let bytes = Data(base64Encoded: value) else { return false }
        return bytes.count == 32 && bytes.base64EncodedString() == value
    }

    private static func hash(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    private static func hexHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func cleanBaseURL(_ url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
            parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
            parts.port == nil || parts.port == 443, parts.path.isEmpty || parts.path == "/"
        else { return nil }
        parts.scheme = "https"
        parts.host = host.lowercased()
        parts.port = nil
        parts.path = ""
        return parts.url
    }

    private static func namespace(baseURL: URL, environment: String) -> String {
        let origin = (cleanBaseURL(baseURL) ?? baseURL).absoluteString
        return "app-attest.v1." + hexHash(Data("\(origin)|\(environment)".utf8))
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard busy else {
            busy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append((id, continuation))
                if Task.isCancelled { cancelWaiter(id) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().1.resume() }
    }
}

@MainActor
struct SystemAppAttestService: AppAttestServicing {
    var isSupported: Bool {
        !ProcessInfo.processInfo.isiOSAppOnMac && DCAppAttestService.shared.isSupported
    }

    func generateKey() async throws -> String {
        do { return try await DCAppAttestService.shared.generateKey() } catch {
            throw safeError(error)
        }
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        do {
            return try await DCAppAttestService.shared.attestKey(
                keyID, clientDataHash: clientDataHash)
        } catch { throw safeError(error) }
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        do {
            return try await DCAppAttestService.shared.generateAssertion(
                keyID, clientDataHash: clientDataHash)
        } catch { throw safeError(error) }
    }

    private func safeError(_ error: Error) -> Error {
        if Task.isCancelled { return CancellationError() }
        let error = error as NSError
        guard error.domain == DCErrorDomain else {
            return AppAttestClientError.appleFailure(code: error.code)
        }
        switch error.code {
        case DCError.featureUnsupported.rawValue: return AppAttestClientError.unsupported
        case DCError.serverUnavailable.rawValue: return AppAttestClientError.appleUnavailable
        case DCError.invalidKey.rawValue: return AppAttestClientError.appleInvalidKey
        default: return AppAttestClientError.appleFailure(code: error.code)
        }
    }
}

/// Enrollment checkpoints must survive a failed update. The general provider store uses
/// delete/add replacement, so this small adapter updates the existing item atomically.
@MainActor
struct AppAttestKeychainStore: KeychainStoring {
    private let service =
        (Bundle.main.bundleIdentifier ?? "com.gigabeyond.framereply") + ".app-attest"

    func set(_ value: String, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let changes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(changes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
    }

    func get(account: String) throws -> String? {
        try KeychainStore(service: service).get(account: account)
    }
    func delete(account: String) throws {
        try KeychainStore(service: service).delete(account: account)
    }
}

private nonisolated final class RejectAppAttestRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
