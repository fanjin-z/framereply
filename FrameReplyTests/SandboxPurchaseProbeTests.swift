#if DEBUG
    import StoreKit
    import XCTest

    @testable import FrameReply

    final class SandboxPurchaseProbeTests: XCTestCase {
        private let productID = "test.subscription.monthly"

        func testConfigurationPersistsForHomeScreenLaunchAndUsesNewSchemeOverrides() throws {
            let suite = "SandboxPurchaseProbeTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            XCTAssertThrowsError(
                try SandboxPurchaseConfiguration.load(environment: [:], defaults: defaults))

            let environment = [
                "SANDBOX_API_URL": "https://sandbox.example", "SANDBOX_PRODUCT_ID": productID
            ]
            _ = try SandboxPurchaseConfiguration.load(environment: environment, defaults: defaults)
            let reopened = try SandboxPurchaseConfiguration.load(
                environment: [:], defaults: defaults)
            XCTAssertEqual(reopened.baseURL.absoluteString, "https://sandbox.example")
            XCTAssertEqual(reopened.productID, productID)

            let changed = try SandboxPurchaseConfiguration.load(
                environment: ["SANDBOX_API_URL": "https://new-sandbox.example"], defaults: defaults)
            XCTAssertEqual(changed.baseURL.absoluteString, "https://new-sandbox.example")
            XCTAssertEqual(changed.productID, productID)
        }

        func testConfigurationAndEvidenceRejectUnsafeOrNonSandboxInputs() throws {
            for url in [
                "http://sandbox.example", "https://user:password@sandbox.example",
                "https://sandbox.example?token=secret", "https://sandbox.example/unexpected-path"
            ] {
                XCTAssertThrowsError(try configuration(url: url))
            }
            XCTAssertThrowsError(try SandboxPurchaseConfiguration(environment: [:]))
            let authenticationOnly = try SandboxPurchaseConfiguration(
                environment: ["SANDBOX_API_URL": "https://sandbox.example"],
                appAttestEnvironment: "development")
            XCTAssertTrue(authenticationOnly.productID.isEmpty)
            XCTAssertThrowsError(
                try authenticationOnly.validate(environment: .sandbox, productID: ""))
            XCTAssertThrowsError(
                try SandboxPurchaseConfiguration(
                    environment: ["SANDBOX_API_URL": "https://sandbox.example"],
                    appAttestEnvironment: "unknown"))
            let config = try configuration()
            XCTAssertNoThrow(try config.validate(environment: .sandbox, productID: productID))
            for environment: AppStore.Environment in [.production, .xcode] {
                XCTAssertThrowsError(
                    try config.validate(environment: environment, productID: productID))
            }
            XCTAssertThrowsError(
                try config.validate(environment: .sandbox, productID: "other.product"))
        }

        @MainActor
        func testAuthenticationNeedsNoPurchaseAndRejectsUnconfirmedStatus() async throws {
            let authentication = ProbeAuthenticationStub()
            let config = try SandboxPurchaseConfiguration(
                environment: ["SANDBOX_API_URL": "https://sandbox.example"],
                appAttestEnvironment: "development")
            let client = SandboxSubscriptionClient(
                configuration: config, authentication: authentication)
            authentication.response = Data("{\"authenticated\":true}".utf8)
            try await client.checkAuthentication()
            XCTAssertEqual(authentication.calls.count, 1)
            XCTAssertEqual(authentication.calls[0].0, .status)
            XCTAssertEqual(authentication.calls[0].1, Data("{}".utf8))
            for body in ["{\"authenticated\":false}", "synthetic.signed.evidence"] {
                authentication.response = Data(body.utf8)
                do {
                    try await client.checkAuthentication()
                    XCTFail("Expected malformed status to fail")
                } catch let error as SandboxPurchaseError {
                    XCTAssertFalse(error.message.contains("synthetic.signed.evidence"))
                }
            }
        }

        @MainActor
        func testVerificationSendsOnlySignedEvidenceAndAcceptsExpiredEntitlement() async throws {
            let authentication = ProbeAuthenticationStub()
            authentication.response = Data(response().utf8)
            let client = SandboxSubscriptionClient(
                configuration: try configuration(), authentication: authentication)
            let entitlement = try await client.verify(
                signedTransactionInfo: "synthetic.signed.evidence")

            XCTAssertFalse(entitlement.active)
            XCTAssertEqual(entitlement.status, "expired")
            XCTAssertEqual(entitlement.period.id, "period-id")
            XCTAssertEqual(authentication.calls.count, 1)
            XCTAssertEqual(authentication.calls[0].0, .subscription)
            let body =
                try JSONSerialization.jsonObject(with: authentication.calls[0].1)
                as? [String: String]
            XCTAssertEqual(body, ["signedTransactionInfo": "synthetic.signed.evidence"])
        }

        @MainActor
        func testVerificationRejectsMalformedOrMismatchedResponsesWithoutEchoingPayloads()
            async throws
        {
            let authentication = ProbeAuthenticationStub()
            let client = SandboxSubscriptionClient(
                configuration: try configuration(), authentication: authentication)
            for body in [
                response(environment: "Production"),
                response(product: "other.product"),
                "synthetic.signed.evidence"
            ] {
                authentication.response = Data(body.utf8)
                do {
                    _ = try await client.verify(signedTransactionInfo: "synthetic.signed.evidence")
                    XCTFail("Expected response rejection")
                } catch let error as SandboxPurchaseError {
                    XCTAssertFalse(error.message.contains("synthetic.signed.evidence"))
                    XCTAssertTrue(error.message.contains("Recheck purchase"))
                }
            }
            authentication.error = .backend(status: 401, code: "UNAUTHENTICATED")
            do {
                _ = try await client.verify(signedTransactionInfo: "synthetic.signed.evidence")
                XCTFail("Expected authentication rejection")
            } catch let error as SandboxPurchaseError {
                XCTAssertTrue(error.message.contains("Recheck purchase"))
            }
        }

        private func configuration(url: String = "https://sandbox.example") throws
            -> SandboxPurchaseConfiguration
        {
            try SandboxPurchaseConfiguration(
                environment: [
                    "SANDBOX_API_URL": url, "SANDBOX_PRODUCT_ID": productID
                ], appAttestEnvironment: "development")
        }

        private func response(
            environment: String = "Sandbox", product: String = "test.subscription.monthly"
        ) -> String {
            """
            {"entitlement": {
              "subscriptionId": "subscription-id", "environment": "\(environment)",
              "productId": "\(product)", "active": false, "status": "expired",
              "accessUntil": "2026-09-18T00:00:00.000Z", "willRenew": false,
              "period": {"id": "period-id", "kind": "trial",
                "startsAt": "2026-09-11T00:00:00.000Z", "expiresAt": "2026-09-18T00:00:00.000Z"},
              "verifiedAt": "2026-09-18T01:00:00.000Z"
            }}
            """
        }
    }
    @MainActor
    private final class ProbeAuthenticationStub: AppAttestAuthenticating {
        var response = Data()
        var error: AppAttestClientError?
        var calls: [(AppAttestOperation, Data)] = []

        func post(operation: AppAttestOperation, body: Data) async throws -> Data {
            calls.append((operation, body))
            if let error { throw error }
            return response
        }
    }
#endif
