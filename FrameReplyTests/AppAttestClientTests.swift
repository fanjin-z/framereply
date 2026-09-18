import CryptoKit
import XCTest

@testable import FrameReply

@MainActor
final class AppAttestClientTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private let clientBytes = Data("server data\n  exact bytes".utf8)

    override func setUp() {
        super.setUp()
        AnalysisURLProtocolStub.reset()
    }

    func testExactBodyAndDecodedChallengeAreHashedAndEnrollmentSurvivesRelaunch() async throws {
        let service = AttestServiceStub()
        let storage = AttestStorageStub()
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = makeClient(service: service, storage: storage, session: session)
        let body = Data("{ \"signedTransactionInfo\" : \"synthetic.evidence\" }\n".utf8)
        queueEnrollment()
        queueProtected(response: "{\"ok\":true}")
        _ = try await client.post(operation: .subscription, body: body)

        let requests = AnalysisURLProtocolStub.requests
        XCTAssertEqual(
            requests.map { $0.url!.path },
            [
                "/v1/auth/challenges", "/v1/auth/attest", "/v1/auth/challenges",
                "/v1/subscriptions/verify"
            ])
        let first = try jsonBody(requests[0])
        XCTAssertEqual(first["operation"], "attest")
        XCTAssertNil(first["bodyHash"])
        XCTAssertEqual(try jsonBody(requests[2])["bodyHash"], hexHash(body))
        XCTAssertEqual(requests[3].httpBody, body)
        XCTAssertEqual(
            requests[3].value(forHTTPHeaderField: "X-App-Attest-Key-Id"), service.keys[0])
        XCTAssertNotNil(requests[3].value(forHTTPHeaderField: "X-App-Attest-Challenge-Id"))
        XCTAssertEqual(
            requests[3].value(forHTTPHeaderField: "X-App-Attest-Assertion"),
            Data("assertion-1".utf8).base64EncodedString())
        XCTAssertEqual(service.attestationHashes, [Data(SHA256.hash(data: clientBytes))])
        XCTAssertEqual(service.assertionHashes, [Data(SHA256.hash(data: clientBytes))])

        // A second instance stands in for an app restart and must use persisted enrollment.
        let reopened = makeClient(service: service, storage: storage, session: session)
        queueProtected()
        _ = try await reopened.post(operation: .status, body: Data("{}".utf8))
        XCTAssertEqual(service.keys.count, 1)
        XCTAssertEqual(service.attestationHashes.count, 1)
        XCTAssertEqual(service.assertionHashes.count, 2)
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 6)
    }

    func testFullOperationsSerializeAndCancellingAWaiterDoesNotReleaseActiveCall() async throws {
        let service = AttestServiceStub()
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = makeClient(service: service, session: session)
        queueEnrollment()
        queueProtected()
        queueProtected()
        let entered = expectation(description: "First assertion entered")
        var resume: CheckedContinuation<Void, Never>?
        service.beforeAssertion = {
            service.beforeAssertion = nil
            entered.fulfill()
            await withCheckedContinuation { resume = $0 }
        }
        let first = Task { try await client.post(operation: .status, body: Data("{}".utf8)) }
        await fulfillment(of: [entered], timeout: 2)
        let cancelled = Task { try await client.post(operation: .status, body: Data("{}".utf8)) }
        let last = Task { try await client.post(operation: .status, body: Data("{}".utf8)) }
        for _ in 0..<5 { await Task.yield() }
        cancelled.cancel()
        await assertThrowsErrorAsync {
            _ = try await cancelled.value
        } errorHandler: {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(
            AnalysisURLProtocolStub.requests.count, 3,
            "No second challenge may overtake the first assertion")
        resume?.resume()
        _ = try await first.value
        _ = try await last.value
        XCTAssertEqual(service.keys.count, 1)
        XCTAssertEqual(service.assertionHashes.count, 2)
        XCTAssertEqual(
            AnalysisURLProtocolStub.requests.map { $0.url!.path },
            [
                "/v1/auth/challenges", "/v1/auth/attest", "/v1/auth/challenges", "/v1/auth/status",
                "/v1/auth/challenges", "/v1/auth/status"
            ])
    }

    func testUncertainRegistrationChecksStatusWithoutReattestingOrReplacingKey() async throws {
        let service = AttestServiceStub()
        let storage = AttestStorageStub()
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        AnalysisURLProtocolStub.responses = [(200, challenge()), (503, failure("AUTH_UNAVAILABLE"))]
        await assertThrowsErrorAsync {
            _ = try await self.makeClient(service: service, storage: storage, session: session)
                .post(operation: .status, body: Data("{}".utf8))
        } errorHandler: {
            XCTAssertEqual(
                $0 as? AppAttestClientError, .backend(status: 503, code: "AUTH_UNAVAILABLE"))
        }

        // The previous request might have committed even though no success reached the app.
        queueProtected()
        queueProtected()
        _ = try await makeClient(service: service, storage: storage, session: session)
            .post(operation: .status, body: Data("{}".utf8))
        XCTAssertEqual(service.keys.count, 1)
        XCTAssertEqual(service.attestationHashes.count, 1)
        XCTAssertEqual(
            AnalysisURLProtocolStub.requests.filter { $0.url?.path == "/v1/auth/attest" }.count, 1)
    }

    func testUncertainUnregisteredProofIsResentButExpiredOrDisabledIdentityIsNotReplaced()
        async throws
    {
        let service = AttestServiceStub()
        let storage = AttestStorageStub()
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        AnalysisURLProtocolStub.responses = [(200, challenge()), (503, failure("AUTH_UNAVAILABLE"))]
        await assertThrowsErrorAsync({
            _ = try await self.makeClient(service: service, storage: storage, session: session)
                .post(operation: .status, body: Data("{}".utf8))
        })
        let originalBody = try jsonBody(AnalysisURLProtocolStub.requests[1])
        AnalysisURLProtocolStub.responses = [
            (401, failure("UNAUTHENTICATED")), (200, "{\"registered\":true}")
        ]
        queueProtected()
        _ = try await makeClient(service: service, storage: storage, session: session)
            .post(operation: .status, body: Data("{}".utf8))
        XCTAssertEqual(try jsonBody(AnalysisURLProtocolStub.requests[3]), originalBody)
        XCTAssertEqual(service.attestationHashes.count, 1)

        // Registered 401 may mean disabled: never let it trigger a fresh identity.
        AnalysisURLProtocolStub.responses = [(401, failure("UNAUTHENTICATED"))]
        await assertThrowsErrorAsync {
            _ = try await self.makeClient(service: service, storage: storage, session: session)
                .post(operation: .status, body: Data("{}".utf8))
        } errorHandler: {
            XCTAssertEqual(
                $0 as? AppAttestClientError, .backend(status: 401, code: "UNAUTHENTICATED"))
        }
        XCTAssertEqual(service.keys.count, 1)

        let pendingStorage = AttestStorageStub()
        AnalysisURLProtocolStub.responses = [(200, challenge()), (503, failure("AUTH_UNAVAILABLE"))]
        await assertThrowsErrorAsync({
            _ = try await self.makeClient(
                service: service, storage: pendingStorage, session: session
            )
            .post(operation: .status, body: Data("{}".utf8))
        })
        let keysBefore = service.keys.count
        AnalysisURLProtocolStub.responses = [(401, failure("UNAUTHENTICATED"))]
        await assertThrowsErrorAsync {
            _ = try await self.makeClient(
                service: service, storage: pendingStorage, session: session,
                now: self.instant.addingTimeInterval(301)
            )
            .post(operation: .status, body: Data("{}".utf8))
        } errorHandler: {
            XCTAssertEqual($0 as? AppAttestClientError, .enrollmentUncertain)
        }
        XCTAssertEqual(service.keys.count, keysBefore)
    }

    func testAppleTransientFailureRetainsExactInputsAcrossRelaunch() async throws {
        let service = AttestServiceStub()
        service.attestationErrors = [.appleUnavailable]
        let storage = AttestStorageStub()
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        AnalysisURLProtocolStub.responses = [(200, challenge())]
        await assertThrowsErrorAsync {
            _ = try await self.makeClient(service: service, storage: storage, session: session)
                .post(operation: .status, body: Data("{}".utf8))
        } errorHandler: {
            XCTAssertEqual($0 as? AppAttestClientError, .appleUnavailable)
        }
        AnalysisURLProtocolStub.responses = [(200, "{\"registered\":true}")]
        queueProtected()
        _ = try await makeClient(service: service, storage: storage, session: session)
            .post(operation: .status, body: Data("{}".utf8))
        XCTAssertEqual(service.keys.count, 1)
        XCTAssertEqual(service.attestationHashes.count, 2)
        XCTAssertEqual(service.attestationHashes[0], service.attestationHashes[1])
        XCTAssertEqual(
            AnalysisURLProtocolStub.requests.filter { (try? jsonBody($0)["operation"]) == "attest" }
                .count, 1)
    }

    func testPermanentAppleFailureAllowsOnlyOneReplacementUntilEnrollmentSucceeds() async throws {
        for error: AppAttestClientError in [.appleInvalidKey, .appleFailure(code: 0)] {
            AnalysisURLProtocolStub.reset()
            let service = AttestServiceStub()
            service.attestationErrors = [error, error, error]
            let storage = AttestStorageStub()
            let session = makeSession()
            defer { session.invalidateAndCancel() }
            AnalysisURLProtocolStub.responses = [(200, challenge()), (200, challenge())]
            await assertThrowsErrorAsync({
                _ = try await self.makeClient(service: service, storage: storage, session: session)
                    .post(operation: .status, body: Data("{}".utf8))
            })
            XCTAssertEqual(service.keys.count, 2)
            await assertThrowsErrorAsync({
                _ = try await self.makeClient(service: service, storage: storage, session: session)
                    .post(operation: .status, body: Data("{}".utf8))
            })
            XCTAssertEqual(service.keys.count, 2, "A repeated tap must not mint more keys")
        }
    }

    func testKeychainWriteFailureKeepsNewIdentifierUntilItCanBeSaved() async throws {
        let service = AttestServiceStub()
        let storage = AttestStorageStub()
        storage.failWrites = true
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = makeClient(service: service, storage: storage, session: session)
        await assertThrowsErrorAsync {
            _ = try await client.post(operation: .status, body: Data("{}".utf8))
        } errorHandler: {
            XCTAssertEqual($0 as? AppAttestClientError, .storage)
        }
        XCTAssertTrue(AnalysisURLProtocolStub.requests.isEmpty)
        storage.failWrites = false
        queueEnrollment()
        queueProtected()
        _ = try await client.post(operation: .status, body: Data("{}".utf8))
        XCTAssertEqual(service.keys.count, 1)
    }

    func testUnsupportedAndInvalidConfigurationFailBeforeNetworkAndErrorsNeverEchoPayloads()
        async throws
    {
        let service = AttestServiceStub()
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        service.isSupported = false
        await assertThrowsErrorAsync {
            _ = try await self.makeClient(service: service, session: session).post(
                operation: .status, body: Data("{}".utf8))
        } errorHandler: {
            XCTAssertEqual($0 as? AppAttestClientError, .unsupported)
        }
        service.isSupported = true
        for address in [
            "http://sandbox.example", "https://u:p@sandbox.example",
            "https://sandbox.example?key=secret", "https://sandbox.example/nested",
            "https://sandbox.example:444"
        ] {
            let client = AppAttestClient(
                baseURL: URL(string: address)!, environment: "development", session: session,
                service: service, storage: AttestStorageStub())
            await assertThrowsErrorAsync {
                _ = try await client.post(operation: .status, body: Data("{}".utf8))
            } errorHandler: {
                XCTAssertEqual($0 as? AppAttestClientError, .invalidConfiguration)
            }
        }
        XCTAssertTrue(service.keys.isEmpty)
        XCTAssertTrue(AnalysisURLProtocolStub.requests.isEmpty)
        let client = makeClient(service: service, session: session)
        for (status, response) in [
            (401, failure("secret-proof")), (307, "secret-proof"), (200, "secret-proof")
        ] {
            AnalysisURLProtocolStub.responses = [(status, response)]
            await assertThrowsErrorAsync {
                _ = try await client.post(operation: .status, body: Data("{}".utf8))
            } errorHandler: {
                XCTAssertFalse($0.localizedDescription.contains("secret-proof"))
            }
        }
        XCTAssertEqual(service.keys.count, 1, "Backend errors do not rotate device identities")
    }

    func testSharedClientNormalizesOriginAndSeparatesAttestationEnvironments() {
        let client = AppAttestClient.shared(
            baseURL: URL(string: "https://example.test")!, environment: "development")
        XCTAssertTrue(
            client
                === AppAttestClient.shared(
                    baseURL: URL(string: "https://EXAMPLE.test:443/")!, environment: "development"))
        XCTAssertFalse(
            client
                === AppAttestClient.shared(
                    baseURL: URL(string: "https://example.test")!, environment: "production"))
        XCTAssertFalse(
            client
                === AppAttestClient.shared(
                    baseURL: URL(string: "https://other.example.test")!, environment: "development")
        )
    }

    private func makeClient(
        service: AttestServiceStub, storage: AttestStorageStub? = nil, session: URLSession,
        now: Date? = nil
    ) -> AppAttestClient {
        let date = now ?? instant
        return AppAttestClient(
            baseURL: URL(string: "https://sandbox.example")!, environment: "development",
            session: session, service: service, storage: storage ?? AttestStorageStub(),
            now: { date })
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func queueEnrollment() {
        AnalysisURLProtocolStub.responses += [(200, challenge()), (200, "{\"registered\":true}")]
    }

    private func queueProtected(response: String = "{\"authenticated\":true}") {
        AnalysisURLProtocolStub.responses += [(200, challenge()), (200, response)]
    }

    private func challenge() -> String {
        let expires = ISO8601DateFormatter().string(from: instant.addingTimeInterval(300))
        return
            "{\"challengeId\":\"\(UUID().uuidString.lowercased())\",\"clientData\":\"\(clientBytes.base64EncodedString())\",\"expiresAt\":\"\(expires)\"}"
    }

    private func failure(_ code: String) -> String {
        "{\"error\":{\"code\":\"\(code)\",\"message\":\"secret-proof\"}}"
    }
    private func jsonBody(_ request: URLRequest) throws -> [String: String] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
    }
    private func hexHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private final class AttestServiceStub: AppAttestServicing {
    var isSupported = true
    var keys: [String] = []
    var attestationHashes: [Data] = []
    var assertionHashes: [Data] = []
    var attestationErrors: [AppAttestClientError] = []
    var beforeAssertion: (() async -> Void)?

    func generateKey() async throws -> String {
        let key = Data(repeating: UInt8(keys.count + 1), count: 32).base64EncodedString()
        keys.append(key)
        return key
    }
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        attestationHashes.append(clientDataHash)
        if !attestationErrors.isEmpty { throw attestationErrors.removeFirst() }
        return Data("synthetic-attestation".utf8)
    }
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        assertionHashes.append(clientDataHash)
        await beforeAssertion?()
        return Data("assertion-\(assertionHashes.count)".utf8)
    }
}

@MainActor
private final class AttestStorageStub: KeychainStoring {
    var values: [String: String] = [:]
    var failWrites = false

    func set(_ value: String, for account: String) throws {
        if failWrites { throw AppAttestClientError.storage }
        values[account] = value
    }
    func get(account: String) throws -> String? { values[account] }
    func delete(account: String) throws { values[account] = nil }
}
