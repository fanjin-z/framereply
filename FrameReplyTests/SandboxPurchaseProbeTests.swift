#if DEBUG
    import StoreKit
    import XCTest

    @testable import FrameReply

    final class SandboxPurchaseProbeTests: XCTestCase {
        private let productID = "test.subscription.monthly"

        override func setUp() {
            super.setUp()
            AnalysisURLProtocolStub.reset()
        }

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
                "https://sandbox.example?token=secret"
            ] {
                XCTAssertThrowsError(try configuration(url: url))
            }
            XCTAssertThrowsError(try SandboxPurchaseConfiguration(environment: [:]))
            let config = try configuration()
            XCTAssertNoThrow(try config.validate(environment: .sandbox, productID: productID))
            for environment: AppStore.Environment in [.production, .xcode] {
                XCTAssertThrowsError(
                    try config.validate(environment: environment, productID: productID))
            }
            XCTAssertThrowsError(
                try config.validate(environment: .sandbox, productID: "other.product"))
        }

        func testVerificationSendsOnlySignedEvidenceAndAcceptsExpiredEntitlement() async throws {
            AnalysisURLProtocolStub.stub(statusCode: 200, body: response())
            let session = makeSession()
            defer { session.invalidateAndCancel() }
            let client = SandboxSubscriptionClient(
                configuration: try configuration(), session: session)
            let entitlement = try await client.verify(
                signedTransactionInfo: "synthetic.signed.evidence")

            XCTAssertFalse(entitlement.active)
            XCTAssertEqual(entitlement.status, "expired")
            XCTAssertEqual(entitlement.period.id, "period-id")
            let request = try XCTUnwrap(AnalysisURLProtocolStub.requests.first)
            XCTAssertEqual(
                request.url?.absoluteString, "https://sandbox.example/v1/subscriptions/verify")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body =
                try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody))
                as? [String: String]
            XCTAssertEqual(body, ["signedTransactionInfo": "synthetic.signed.evidence"])
        }

        func testVerificationRejectsMalformedOrMismatchedResponsesWithoutEchoingPayloads()
            async throws
        {
            let session = makeSession()
            defer { session.invalidateAndCancel() }
            let client = SandboxSubscriptionClient(
                configuration: try configuration(), session: session)
            for (status, body) in [
                (200, response(environment: "Production")),
                (200, response(product: "other.product")),
                (200, "synthetic.signed.evidence"),
                (401, "synthetic.signed.evidence"),
                (404, "synthetic.signed.evidence"),
                (503, "synthetic.signed.evidence"),
                (307, "synthetic.signed.evidence")
            ] {
                AnalysisURLProtocolStub.stub(statusCode: status, body: body)
                do {
                    _ = try await client.verify(signedTransactionInfo: "synthetic.signed.evidence")
                    XCTFail("Expected rejection for HTTP \(status)")
                } catch let error as SandboxPurchaseError {
                    XCTAssertFalse(error.message.contains("synthetic.signed.evidence"))
                    XCTAssertTrue(error.message.contains("Recheck purchase"))
                }
            }
        }

        private func configuration(url: String = "https://sandbox.example") throws
            -> SandboxPurchaseConfiguration
        {
            try SandboxPurchaseConfiguration(environment: [
                "SANDBOX_API_URL": url, "SANDBOX_PRODUCT_ID": productID
            ])
        }

        private func makeSession() -> URLSession {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [AnalysisURLProtocolStub.self]
            return URLSession(configuration: config)
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
#endif
