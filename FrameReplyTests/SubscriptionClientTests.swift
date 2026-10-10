#if DEBUG
    import StoreKit
    import XCTest

    @testable import FrameReply

    final class SubscriptionClientTests: XCTestCase {
        private let productID = "test.subscription.monthly"

        func testAllowancePresentationDistinguishesLowExhaustedAndUnavailableUsage() throws {
            let decoder = JSONDecoder()
            func usage(_ changes: [String: Any] = [:]) throws -> SubscriptionUsage {
                var body = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Data(usageResponse().utf8)) as? [String: Any]
                )
                body.merge(changes) { _, new in new }
                return try decoder.decode(
                    SubscriptionUsage.self, from: JSONSerialization.data(withJSONObject: body))
            }
            for (remaining, fraction, level): (Int, Double, AIAccessPresentation.UsageLevel) in [
                (700_000, 0.7, .available), (200_000, 0.2, .low), (0, 0, .exhausted)
            ] {
                let value = try XCTUnwrap(
                    AIAccessPresentation.remainingFraction(
                        usage([
                            "remainingMicrousd": remaining,
                            "availability": remaining == 0 ? "exhausted" : "available"
                        ])))
                XCTAssertEqual(value, fraction, accuracy: 0.001)
                XCTAssertEqual(AIAccessPresentation.usageLevel(value), level)
            }
            for changes: [String: Any] in [
                ["stale": true], ["remainingMicrousd": NSNull()],
                ["availability": "recovery_required"], ["budgetMicrousd": 0]
            ] {
                XCTAssertNil(AIAccessPresentation.remainingFraction(try usage(changes)))
            }
        }

        func testOfferDurationUsesStorePeriodAndCountInsteadOfSevenDayAssumption() throws {
            let locale = Locale(identifier: "en_US")
            for unit: Product.SubscriptionPeriod.Unit in [.day, .week, .month, .year] {
                let singlePeriod = try XCTUnwrap(
                    AIAccessPresentation.duration(value: 1, unit: unit, locale: locale)
                )
                let repeatedPeriod = try XCTUnwrap(
                    AIAccessPresentation.duration(value: 1, unit: unit, count: 2, locale: locale)
                )
                let totalPeriod = try XCTUnwrap(
                    AIAccessPresentation.duration(value: 2, unit: unit, locale: locale)
                )
                XCTAssertEqual(repeatedPeriod, totalPeriod)
                XCTAssertNotEqual(singlePeriod, totalPeriod)
            }
            XCTAssertNil(AIAccessPresentation.duration(value: 0, unit: .day, locale: locale))
            XCTAssertFalse(
                try XCTUnwrap(
                    AIAccessPresentation.billingPeriod(value: 1, unit: .month, locale: locale)
                ).isEmpty
            )
            XCTAssertEqual(
                AIAccessPresentation.billingPeriod(value: 3, unit: .month, locale: locale),
                AIAccessPresentation.duration(value: 3, unit: .month, locale: locale))
        }

        func testConfigurationRoutesVerifiedEnvironmentsAndRejectsUnsafeInputs() throws {
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
            for environment: AppStore.Environment in [.sandbox, .production] {
                let automatic = try SubscriptionConfiguration(
                    apiURL: "https://production.example", sandboxAPIURL: "https://sandbox.example",
                    productID: productID, appAttestEnvironment: "production",
                    storeEnvironment: "Automatic", verifiedAppEnvironment: environment)
                XCTAssertEqual(
                    automatic.baseURL.host,
                    environment == .sandbox ? "sandbox.example" : "production.example")
                XCTAssertEqual(automatic.appAttestEnvironment, "production")
                XCTAssertNoThrow(
                    try automatic.validate(environment: environment, productID: productID))
                XCTAssertThrowsError(
                    try automatic.validate(
                        environment: environment == .sandbox ? .production : .sandbox,
                        productID: productID))
            }
            for environment: AppStore.Environment? in [nil, .xcode] {
                XCTAssertThrowsError(
                    try SubscriptionConfiguration(
                        apiURL: "https://production.example",
                        sandboxAPIURL: "https://sandbox.example",
                        productID: productID, appAttestEnvironment: "production",
                        storeEnvironment: "Automatic", verifiedAppEnvironment: environment))
            }
            for sandboxURL in ["", "http://sandbox.example", "https://production.example"] {
                XCTAssertThrowsError(
                    try SubscriptionConfiguration(
                        apiURL: "https://production.example", sandboxAPIURL: sandboxURL,
                        productID: productID, appAttestEnvironment: "production",
                        storeEnvironment: "Automatic", verifiedAppEnvironment: .production))
            }
            XCTAssertThrowsError(
                try SubscriptionConfiguration(
                    apiURL: "https://production.example", sandboxAPIURL: "https://sandbox.example",
                    productID: productID, appAttestEnvironment: "development",
                    storeEnvironment: "Automatic", verifiedAppEnvironment: .sandbox))
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
                }
            }
            authentication.error = .backend(status: 401, code: "UNAUTHENTICATED")
            do {
                _ = try await client.verify(signedTransactionInfo: "synthetic.signed.evidence")
                XCTFail("Expected authentication rejection")
            } catch let error as SubscriptionClientError {
                // Preserve the cause for diagnostics without exposing signed purchase evidence.
                XCTAssertEqual(
                    error.authenticationError, .backend(status: 401, code: "UNAUTHENTICATED"))
                XCTAssertFalse(error.message.contains("synthetic.signed.evidence"))
            }
        }

        @MainActor
        func testManagedCredentialAndUsageUseBoundSubscriptionAndRejectWrongUsage() async throws {
            let authentication = ProbeAuthenticationStub()
            let client = SubscriptionClient(
                configuration: try configuration(), authentication: authentication)
            let version = String(repeating: "a", count: 64)
            authentication.response = Data(
                """
                {"consent":{"version":"\(version)","recipients":[{"id":"example","name":"Example AI"}]}}
                """.utf8)
            let consent = try await client.aiConsent()
            XCTAssertEqual(consent.recipients.first?.name, "Example AI")
            let configurationResponse = authentication.response
            for replacement in ["[]", "[{\"id\":\"example\",\"name\":\"\"}]"] {
                authentication.response = Data(
                    String(decoding: configurationResponse, as: UTF8.self)
                        .replacingOccurrences(
                            of: "[{\"id\":\"example\",\"name\":\"Example AI\"}]", with: replacement
                        ).utf8)
                do {
                    _ = try await client.aiConsent()
                    XCTFail("Missing recipient disclosure must not permit connection")
                } catch is SubscriptionClientError {}
            }
            authentication.calls.removeAll()
            authentication.response = Data(
                """
                {"consentVersion":"\(version)","aiProvider":"openrouter","model":"openai/gpt-6-luna",
                "responseModel":"openai/gpt-6-luna-20260922",
                "apiKey":"synthetic-secret","expiresAt":"2026-09-25T00:00:00.000Z"}
                """.utf8)
            let credential = try await client.credential(
                serviceSubscriptionId: "subscription-id", consent: consent)
            XCTAssertEqual(credential.aiProvider, "openrouter")
            XCTAssertEqual(credential.model, "openai/gpt-6-luna")
            XCTAssertEqual(credential.responseModel, "openai/gpt-6-luna-20260922")
            XCTAssertEqual(credential.apiKey, "synthetic-secret")

            let credentialResponse = authentication.response
            authentication.response = Data(
                String(decoding: credentialResponse, as: UTF8.self)
                    .replacingOccurrences(of: version, with: String(repeating: "b", count: 64)).utf8
            )
            do {
                _ = try await client.credential(
                    serviceSubscriptionId: "subscription-id", consent: consent)
                XCTFail("A different consent scope must never be accepted with a credential")
            } catch is SubscriptionClientError {}
            authentication.calls.removeLast()
            authentication.response = Data(usageResponse().utf8)
            let usage = try await client.usage(serviceSubscriptionId: "subscription-id")
            XCTAssertEqual(usage.remainingMicrousd, 700_000)
            XCTAssertEqual(authentication.calls.map { $0.0 }, [.credential, .usage])
            for (operation, data) in authentication.calls {
                let body = try JSONSerialization.jsonObject(with: data) as? [String: String]
                var expected = ["serviceSubscriptionId": "subscription-id"]
                if operation == .credential { expected["consentVersion"] = version }
                XCTAssertEqual(body, expected)
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

        @MainActor
        func testAccessCachesStatusAndUsageIndependentlyAndRetainsSnapshotsOnFailure() async throws
        {
            let authentication = ProbeAuthenticationStub()
            authentication.response = Data(usageResponse().utf8)
            var date = try XCTUnwrap(AIAccessPresentation.date("2026-09-24T00:00:00Z"))
            let active = try entitlement()
            var statusRequests = 0
            var statusFails = false
            let model = AIAccessModel(
                configuration: try configuration(), authentication: authentication, now: { date },
                latestEntitlement: { _ in
                    statusRequests += 1
                    if statusFails { throw SubscriptionClientError(message: "Offline") }
                    return active
                })

            await model.refreshStatusIfNeeded()
            await model.refreshUsageIfNeeded()
            for _ in 0..<2 {
                await model.refreshStatusIfNeeded()
                await model.refreshUsageIfNeeded()
            }
            XCTAssertEqual(statusRequests, 1)
            XCTAssertEqual(authentication.calls.count, 1)
            XCTAssertTrue(model.hasActiveSubscription)
            XCTAssertFalse(model.isBusy)

            date = date.addingTimeInterval(60)
            await model.refreshStatusIfNeeded()
            await model.refreshUsageIfNeeded()
            XCTAssertEqual(statusRequests, 1)
            XCTAssertEqual(authentication.calls.count, 2)
            model.invalidateUsage()
            await model.refreshUsageIfNeeded()
            XCTAssertEqual(authentication.calls.count, 3)
            XCTAssertEqual(statusRequests, 1)

            date = date.addingTimeInterval(240)
            statusFails = true
            authentication.error = .backend(status: 503, code: "UNAVAILABLE")
            let refreshed = await model.refreshStatusIfNeeded()
            await model.refreshUsageIfNeeded()
            XCTAssertFalse(refreshed)
            XCTAssertEqual(statusRequests, 2)
            XCTAssertTrue(model.hasActiveSubscription)
            XCTAssertFalse(model.statusUnavailable)
            XCTAssertEqual(model.usage?.remainingMicrousd, 700_000)
            XCTAssertNil(model.notice)
            XCTAssertFalse(model.isBusy)
        }

        @MainActor
        func testAccessCoalescesRefreshesAndKeepsNewerObserverResult() async throws {
            let started = expectation(description: "Subscription request started")
            var resume: CheckedContinuation<SubscriptionEntitlement?, Never>?
            let active = try entitlement()
            var requests = 0
            let model = AIAccessModel(
                configuration: try configuration(),
                now: { AIAccessPresentation.date("2026-09-24T00:00:00Z")! },
                latestEntitlement: { _ in
                    requests += 1
                    return await withCheckedContinuation {
                        resume = $0
                        started.fulfill()
                    }
                })
            let first = Task { await model.refreshStatusIfNeeded() }
            await fulfillment(of: [started], timeout: 1)
            let second = Task { await model.refreshStatusIfNeeded() }
            await Task.yield()
            XCTAssertEqual(requests, 1)

            model.acceptVerifiedEntitlement(try entitlement(active: false))
            resume?.resume(returning: active)
            _ = await first.value
            _ = await second.value
            XCTAssertEqual(requests, 1)
            XCTAssertFalse(model.hasActiveSubscription)
            XCTAssertEqual(model.entitlement?.active, false)
        }

        @MainActor
        func testAccessReconcilesExpiryBeforeCacheTimeoutAndAcceptsVerifiedGracePeriod()
            async throws
        {
            var date = try XCTUnwrap(AIAccessPresentation.date("2026-09-24T00:00:00Z"))
            var result: SubscriptionEntitlement?
            var requests = 0
            let model = AIAccessModel(
                configuration: try configuration(), now: { date },
                latestEntitlement: { _ in
                    requests += 1
                    guard let result else { throw SubscriptionClientError(message: "Offline") }
                    return result
                })
            model.acceptVerifiedEntitlement(
                try entitlement(accessUntil: "2026-09-24T00:01:00Z"))
            await model.refreshStatusIfNeeded()
            XCTAssertEqual(requests, 0)

            date = date.addingTimeInterval(60)
            await model.refreshStatusIfNeeded()
            XCTAssertEqual(requests, 1)
            XCTAssertFalse(model.hasActiveSubscription)
            XCTAssertTrue(model.statusUnavailable)

            result = try entitlement(status: "grace_period")
            await model.refreshStatusIfNeeded(force: true)
            XCTAssertEqual(requests, 2)
            XCTAssertTrue(model.hasActiveSubscription)
            XCTAssertFalse(model.statusUnavailable)
        }

        @MainActor
        func testAccessDiscardsOldAllowanceWhenSubscriptionPeriodChanges() async throws {
            let authentication = ProbeAuthenticationStub()
            let started = expectation(description: "Allowance request started")
            var resume: CheckedContinuation<Data, Never>?
            authentication.responder = {
                await withCheckedContinuation {
                    resume = $0
                    started.fulfill()
                }
            }
            let model = AIAccessModel(
                configuration: try configuration(), authentication: authentication,
                now: { AIAccessPresentation.date("2026-09-24T00:00:00Z")! })
            model.acceptVerifiedEntitlement(try entitlement())
            let oldAllowance = Task { await model.refreshUsageIfNeeded() }
            await fulfillment(of: [started], timeout: 1)
            model.acceptVerifiedEntitlement(try entitlement(periodID: "renewed-period"))
            resume?.resume(returning: Data(usageResponse().utf8))
            await oldAllowance.value
            XCTAssertNil(model.usage)

            authentication.responder = nil
            authentication.response = Data(
                usageResponse().replacingOccurrences(of: "period-id", with: "renewed-period").utf8)
            await model.refreshUsageIfNeeded()
            XCTAssertEqual(model.usage?.periodId, "renewed-period")
            XCTAssertEqual(authentication.calls.count, 2)
        }

        @MainActor
        func testAccessForcedRefreshBypassesFreshStatusAndNoPurchaseIsCached() async throws {
            var requests = 0
            let model = AIAccessModel(
                configuration: try configuration(),
                latestEntitlement: { _ in
                    requests += 1
                    return nil
                })
            await model.refreshStatusIfNeeded()
            await model.refreshStatusIfNeeded()
            XCTAssertEqual(requests, 1)
            XCTAssertFalse(model.statusUnavailable)
            XCTAssertFalse(model.hasActiveSubscription)
            await model.refreshStatusIfNeeded(force: true)
            XCTAssertEqual(requests, 2)
        }

        private func entitlement(
            active: Bool = true, accessUntil: String = "2026-09-25T00:00:00Z",
            status: String = "active", periodID: String = "period-id"
        ) throws -> SubscriptionEntitlement {
            var wrapper = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(response().utf8)) as? [String: Any])
            var value = try XCTUnwrap(wrapper["entitlement"] as? [String: Any])
            var period = try XCTUnwrap(value["period"] as? [String: Any])
            period["id"] = periodID
            value["period"] = period
            value["active"] = active
            value["status"] = status
            value["accessUntil"] = accessUntil
            wrapper["entitlement"] = value
            struct Response: Decodable { let entitlement: SubscriptionEntitlement }
            return try JSONDecoder().decode(
                Response.self, from: JSONSerialization.data(withJSONObject: wrapper)
            ).entitlement
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
        var responder: (() async -> Data)?
        var calls: [(AppAttestOperation, Data)] = []

        func post(operation: AppAttestOperation, body: Data) async throws -> Data {
            calls.append((operation, body))
            if let error { throw error }
            if let responder { return await responder() }
            return response
        }
    }
#endif
