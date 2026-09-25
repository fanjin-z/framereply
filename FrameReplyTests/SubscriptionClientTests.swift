#if DEBUG
    import StoreKit
    import XCTest

    @testable import FrameReply

    final class SubscriptionClientTests: XCTestCase {
        private let productID = "test.subscription.monthly"

        func testBackendMicrousdAllowanceDisplaysAsReadableDollars() {
            let locale = Locale(identifier: "en_US")
            XCTAssertEqual(AIAccessPresentation.usd(1_000_000, locale: locale), "$1.00")
            XCTAssertEqual(AIAccessPresentation.usd(700_000, locale: locale), "$0.70")
        }

        func testConfigurationAndEvidenceRejectUnsafeOrNonSandboxInputs() throws {
            for url in [
                "http://sandbox.example", "https://user:password@sandbox.example",
                "https://sandbox.example?token=secret", "https://sandbox.example/unexpected-path"
            ] {
                XCTAssertThrowsError(try configuration(url: url))
            }
            XCTAssertThrowsError(
                try SubscriptionConfiguration(
                    apiURL: "", productID: productID, appAttestEnvironment: "development"))
            XCTAssertThrowsError(
                try SubscriptionConfiguration(
                    apiURL: "https://sandbox.example", productID: "",
                    appAttestEnvironment: "development"))
            let testFlight = try SubscriptionConfiguration(
                apiURL: "https://sandbox.example", productID: productID,
                appAttestEnvironment: "production", storeEnvironment: "Sandbox")
            XCTAssertNoThrow(
                try testFlight.validate(environment: .sandbox, productID: productID))
            XCTAssertThrowsError(
                try SubscriptionConfiguration(
                    apiURL: "https://sandbox.example", productID: productID,
                    appAttestEnvironment: "development", storeEnvironment: "Xcode"))
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
            let config = try configuration()
            let client = SubscriptionClient(
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
                } catch let error as SubscriptionClientError {
                    XCTAssertFalse(error.message.contains("synthetic.signed.evidence"))
                }
            }
        }

        @MainActor
        func testVerificationSendsOnlySignedEvidenceAndAcceptsExpiredEntitlement() async throws {
            let authentication = ProbeAuthenticationStub()
            authentication.response = Data(response().utf8)
            let client = SubscriptionClient(
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
            XCTAssertEqual(entitlement.serviceSubscriptionId, "subscription-id")

            // The updated app also works before the backend identity rename is deployed.
            authentication.response = Data(
                response().replacingOccurrences(
                    of: "serviceSubscriptionId", with: "subscriptionId"
                ).utf8)
            let legacy = try await client.verify(signedTransactionInfo: "synthetic.signed.evidence")
            XCTAssertEqual(legacy.serviceSubscriptionId, entitlement.serviceSubscriptionId)
        }

        @MainActor
        func testVerificationRejectsMalformedOrMismatchedResponsesWithoutEchoingPayloads()
            async throws
        {
            let authentication = ProbeAuthenticationStub()
            let client = SubscriptionClient(
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
                } catch let error as SubscriptionClientError {
                    XCTAssertFalse(error.message.contains("synthetic.signed.evidence"))
                    XCTAssertTrue(error.message.contains("Recheck purchase"))
                }
            }
            authentication.error = .backend(status: 401, code: "UNAUTHENTICATED")
            do {
                _ = try await client.verify(signedTransactionInfo: "synthetic.signed.evidence")
                XCTFail("Expected authentication rejection")
            } catch let error as SubscriptionClientError {
                XCTAssertTrue(error.message.contains("Recheck purchase"))
            }
        }

        @MainActor
        func testManagedCredentialAndUsageUseBoundSubscriptionAndRejectWrongUsage() async throws {
            let authentication = ProbeAuthenticationStub()
            let client = SubscriptionClient(
                configuration: try configuration(), authentication: authentication)
            authentication.response = Data(
                """
                {"aiProvider":"openrouter","model":"openai/gpt-5.6-luna",
                "apiKey":"synthetic-secret","expiresAt":"2026-09-25T00:00:00.000Z"}
                """.utf8)
            let credential = try await client.credential(serviceSubscriptionId: "subscription-id")
            XCTAssertEqual(credential.aiProvider, "openrouter")
            XCTAssertEqual(credential.model, "openai/gpt-5.6-luna")
            XCTAssertEqual(credential.apiKey, "synthetic-secret")

            authentication.response = Data(usageResponse().utf8)
            let usage = try await client.usage(serviceSubscriptionId: "subscription-id")
            XCTAssertEqual(usage.remainingMicrousd, 700_000)
            XCTAssertEqual(authentication.calls.map { $0.0 }, [.credential, .usage])
            for (_, data) in authentication.calls {
                let body = try JSONSerialization.jsonObject(with: data) as? [String: String]
                XCTAssertEqual(body, ["serviceSubscriptionId": "subscription-id"])
            }

            authentication.response = Data(
                usageResponse().replacingOccurrences(
                    of: "subscription-id", with: "other-subscription"
                ).utf8)
            do {
                _ = try await client.usage(serviceSubscriptionId: "subscription-id")
                XCTFail("Expected a mismatched usage response to fail")
            } catch is SubscriptionClientError {
                // The wrong subscription must never be shown as this user's allowance.
            }
        }

        private func configuration(url: String = "https://sandbox.example") throws
            -> SubscriptionConfiguration
        {
            try SubscriptionConfiguration(
                apiURL: url, productID: productID, appAttestEnvironment: "development")
        }

        private func response(
            environment: String = "Sandbox", product: String = "test.subscription.monthly"
        ) -> String {
            """
            {"entitlement": {
              "serviceSubscriptionId": "subscription-id", "environment": "\(environment)",
              "productId": "\(product)", "active": false, "status": "expired",
              "accessUntil": "2026-09-18T00:00:00.000Z", "willRenew": false,
              "period": {"id": "period-id", "kind": "trial",
                "startsAt": "2026-09-11T00:00:00.000Z", "expiresAt": "2026-09-18T00:00:00.000Z"},
              "verifiedAt": "2026-09-18T01:00:00.000Z"
            }}
            """
        }

        private func usageResponse() -> String {
            """
            {"serviceSubscriptionId":"subscription-id","periodId":"period-id",
            "kind":"trial","currency":"USD","budgetMicrousd":1000000,
            "usedMicrousd":300000,"remainingMicrousd":700000,
            "expiresAt":"2026-09-25T00:00:00.000Z","availability":"available",
            "usageAsOf":"2026-09-24T00:00:00.000Z","stale":false}
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
