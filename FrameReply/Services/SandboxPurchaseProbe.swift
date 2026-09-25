#if DEBUG
    import Combine
    import Foundation
    import StoreKit

    @MainActor
    final class SandboxPurchaseProbe: ObservableObject {
        enum Action { case authenticate, buy, recheck }

        let configuration: SandboxPurchaseConfiguration?
        @Published private(set) var isBusy = false
        @Published private(set) var result =
            "Start with Test authentication on a physical iPhone. Purchases also require StoreKit Configuration set to None."

        init() {
            do {
                configuration = try SandboxPurchaseConfiguration.load(
                    environment: ProcessInfo.processInfo.environment)
            } catch {
                configuration = nil
                result = error.localizedDescription
            }
        }

        func run(_ action: Action) async {
            guard !isBusy, let configuration else { return }
            isBusy = true
            result =
                action == .recheck ? "Rechecking the latest purchase…" : "Authenticating this app…"
            defer { isBusy = false }

            do {
                let client = SandboxSubscriptionClient(configuration: configuration)
                if action == .authenticate {
                    try await client.checkAuthentication()
                    result =
                        "App Attest authenticated · \(configuration.appAttestEnvironment). No purchase was made and no AI access was granted."
                    return
                }
                guard !configuration.productID.isEmpty else {
                    throw SandboxPurchaseError(
                        message:
                            "Set SANDBOX_PRODUCT_ID in the unshared Run scheme to test purchases.")
                }
                let evidence: VerificationResult<StoreKit.Transaction>
                switch action {
                case .authenticate:
                    return
                case .buy:
                    // Establish backend authentication before opening Apple's purchase sheet.
                    try await client.checkAuthentication()
                    result = "Opening Apple Sandbox purchase…"
                    let appEvidence: VerificationResult<AppTransaction>
                    if let cached = try? await AppTransaction.shared, case .verified = cached {
                        appEvidence = cached
                    } else {
                        // A fresh Sandbox install may need authentication. This runs only after a tap.
                        appEvidence = try await AppTransaction.refresh()
                    }
                    // Fail before opening a purchase sheet if this is a production or local StoreKit app.
                    guard case .verified(let app) = appEvidence,
                        app.environment == .sandbox
                    else {
                        throw SandboxPurchaseError(
                            message:
                                "An Apple Sandbox app transaction is required. Run a development build with StoreKit Configuration set to None."
                        )
                    }
                    guard
                        let product = try await Product.products(for: [configuration.productID])
                            .first,
                        product.type == .autoRenewable
                    else {
                        throw SandboxPurchaseError(
                            message:
                                "Subscription not found. Check the product ID, App Store Connect setup, and Sandbox account."
                        )
                    }
                    switch try await product.purchase() {
                    case .success(let verification):
                        evidence = verification
                    case .userCancelled:
                        result = "Purchase cancelled."
                        return
                    case .pending:
                        result = "Purchase pending. After Apple approves it, tap Recheck purchase."
                        return
                    @unknown default:
                        throw SandboxPurchaseError(
                            message: "Unexpected StoreKit purchase result. Try Recheck purchase.")
                    }
                case .recheck:
                    // Current entitlements omit expired purchases, which this probe also needs to test.
                    guard
                        let latest = await StoreKit.Transaction.latest(for: configuration.productID)
                    else {
                        throw SandboxPurchaseError(
                            message:
                                "No purchase found for this product and Sandbox account. Buy it first."
                        )
                    }
                    evidence = latest
                }

                let entitlement = try await client.verifyAndFinish(evidence)
                result = entitlement.diagnosticSummary
            } catch is CancellationError {
                result = "Operation cancelled. Retry with Test authentication or Recheck purchase."
            } catch let error as SandboxPurchaseError {
                result = error.message
            } catch {
                // StoreKit/network errors may contain sensitive evidence; never print their payloads.
                let code = (error as NSError).code
                result =
                    "Apple or network operation failed (code \(code)). Check Sandbox sign-in and connectivity. If the purchase completed, use Recheck purchase; otherwise try Buy and verify again."
            }
        }
    }

    nonisolated struct SandboxPurchaseConfiguration {
        let baseURL: URL
        let productID: String
        let appAttestEnvironment: String

        static func load(environment: [String: String], defaults: UserDefaults = .standard) throws
            -> Self
        {
            let keys = ["SANDBOX_API_URL", "SANDBOX_PRODUCT_ID"]
            var values = environment
            for key in keys where values[key] == nil {
                values[key] = defaults.string(forKey: "debug.\(key)")
            }
            let configuration = try Self(environment: values)
            // These are public identifiers, not credentials. Keep Home Screen launches usable after
            // the first configured Xcode run; a new Run environment overrides the saved values.
            for key in keys {
                defaults.set(values[key], forKey: "debug.\(key)")
            }
            return configuration
        }

        init(
            environment: [String: String],
            appAttestEnvironment: String = Bundle.main.object(
                forInfoDictionaryKey: "AppAttestEnvironment") as? String ?? ""
        ) throws {
            guard ["development", "production"].contains(appAttestEnvironment) else {
                throw SandboxPurchaseError(
                    message:
                        "App Attest build configuration is missing. Rebuild the app with Step 4B signing settings."
                )
            }
            guard let rawURL = environment["SANDBOX_API_URL"],
                let url = URL(string: rawURL), url.scheme == "https",
                let host = url.host, !host.isEmpty,
                url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                url.port == nil || url.port == 443,
                url.path.isEmpty || url.path == "/"
            else {
                throw SandboxPurchaseError(
                    message:
                        "Set SANDBOX_API_URL (HTTPS) in an unshared Xcode Run scheme, then run again. Purchases also need SANDBOX_PRODUCT_ID."
                )
            }
            baseURL = url
            productID =
                environment["SANDBOX_PRODUCT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            self.appAttestEnvironment = appAttestEnvironment
        }

        func validate(environment: AppStore.Environment, productID: String) throws {
            guard !self.productID.isEmpty, environment == .sandbox, productID == self.productID
            else {
                throw SandboxPurchaseError(
                    message:
                        "Only the configured product's Apple Sandbox transactions are accepted. Production and local .storekit transactions are blocked."
                )
            }
        }
    }

    nonisolated struct SandboxPurchaseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @MainActor
    struct SandboxSubscriptionClient {
        let configuration: SandboxPurchaseConfiguration
        private let authentication: any AppAttestAuthenticating

        init(
            configuration: SandboxPurchaseConfiguration,
            authentication: (any AppAttestAuthenticating)? = nil
        ) {
            self.configuration = configuration
            self.authentication =
                authentication
                ?? AppAttestClient.shared(
                    baseURL: configuration.baseURL, environment: configuration.appAttestEnvironment)
        }

        func checkAuthentication() async throws {
            let data = try await post(operation: .status, body: Data("{}".utf8))
            struct Status: Decodable { let authenticated: Bool }
            guard let status = try? JSONDecoder().decode(Status.self, from: data),
                status.authenticated
            else {
                throw SandboxPurchaseError(
                    message:
                        "Backend authentication response is malformed. Retry Test authentication.")
            }
        }

        func verify(signedTransactionInfo: String) async throws -> SandboxEntitlement {
            struct Body: Encodable { let signedTransactionInfo: String }
            // Encode once: the authentication client signs and sends these exact bytes.
            let body = try JSONEncoder().encode(Body(signedTransactionInfo: signedTransactionInfo))
            let data = try await post(operation: .subscription, body: body)
            struct Response: Decodable { let entitlement: SandboxEntitlement }
            guard
                let entitlement = try? JSONDecoder().decode(Response.self, from: data).entitlement,
                entitlement.environment == "Sandbox",
                entitlement.productId == configuration.productID
            else {
                throw SandboxPurchaseError(
                    message:
                        "Backend response is malformed or belongs to another environment/product. Purchase remains unfinished; retry with Recheck purchase."
                )
            }
            return entitlement
        }

        func verifyAndFinish(_ evidence: VerificationResult<StoreKit.Transaction>) async throws
            -> SandboxEntitlement
        {
            guard case .verified(let transaction) = evidence else {
                throw SandboxPurchaseError(
                    message:
                        "StoreKit could not verify this transaction. Nothing was sent to the backend."
                )
            }
            try configuration.validate(
                environment: transaction.environment, productID: transaction.productID)
            let entitlement = try await verify(
                signedTransactionInfo: evidence.jwsRepresentation)
            // Leave failed verifications unfinished so StoreKit can deliver them again.
            await transaction.finish()
            return entitlement
        }

        private func post(operation: AppAttestOperation, body: Data) async throws -> Data {
            do {
                return try await authentication.post(operation: operation, body: body)
            } catch let error as AppAttestClientError {
                let retry =
                    operation == .status
                    ? "Retry Test authentication." : "Retry with Recheck purchase."
                throw SandboxPurchaseError(message: "\(error.diagnosticSummary) \(retry)")
            }
        }
    }

    @MainActor
    final class SandboxTransactionObserver: ObservableObject {
        static let shared = SandboxTransactionObserver()

        @Published private(set) var lastResult: String?
        private var updates: Task<Void, Never>?

        func start() {
            guard updates == nil else { return }
            updates = Task {
                for await evidence in StoreKit.Transaction.updates {
                    await process(evidence)
                }
            }
        }

        private func process(_ evidence: VerificationResult<StoreKit.Transaction>) async {
            guard case .verified(let transaction) = evidence else {
                lastResult = "StoreKit delivered an unverified transaction. Use Recheck purchase."
                return
            }
            guard
                let configuration = try? SandboxPurchaseConfiguration.load(
                    environment: ProcessInfo.processInfo.environment),
                transaction.productID == configuration.productID
            else { return }

            do {
                let client = SandboxSubscriptionClient(configuration: configuration)
                let entitlement = try await client.verifyAndFinish(evidence)
                lastResult = "Transaction update verified · \(entitlement.status)."
            } catch {
                // StoreKit will retain an unfinished transaction for retry; never log signed evidence.
                lastResult = "Transaction update could not be verified. Use Recheck purchase."
            }
        }
    }

    nonisolated struct SandboxEntitlement: Decodable {
        struct Period: Decodable {
            let id: String
            let kind: String
            let startsAt: String
            let expiresAt: String
        }
        let serviceSubscriptionId: String
        let environment: String
        let productId: String
        let active: Bool
        let status: String
        let accessUntil: String
        let willRenew: Bool
        let period: Period
        let verifiedAt: String

        private enum CodingKeys: String, CodingKey {
            case serviceSubscriptionId, subscriptionId, environment, productId, active, status
            case accessUntil, willRenew, period, verifiedAt
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            serviceSubscriptionId =
                try values.decodeIfPresent(String.self, forKey: .serviceSubscriptionId)
                ?? values.decode(String.self, forKey: .subscriptionId)
            environment = try values.decode(String.self, forKey: .environment)
            productId = try values.decode(String.self, forKey: .productId)
            active = try values.decode(Bool.self, forKey: .active)
            status = try values.decode(String.self, forKey: .status)
            accessUntil = try values.decode(String.self, forKey: .accessUntil)
            willRenew = try values.decode(Bool.self, forKey: .willRenew)
            period = try values.decode(Period.self, forKey: .period)
            verifiedAt = try values.decode(String.self, forKey: .verifiedAt)
        }

        var diagnosticSummary: String {
            """
            Backend verified · \(environment)
            Status: \(status) · active: \(active)
            Period: \(period.kind) · renews: \(willRenew)
            Access until: \(accessUntil)
            Period start: \(period.startsAt)
            Period end: \(period.expiresAt)
            Verified at: \(verifiedAt)
            FrameReply subscription ID: \(serviceSubscriptionId)
            Period ID: \(period.id)
            """
        }
    }

#endif
