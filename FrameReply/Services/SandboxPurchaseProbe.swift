#if DEBUG
    import Combine
    import Foundation
    import StoreKit

    @MainActor
    final class SandboxPurchaseProbe: ObservableObject {
        enum Action { case buy, recheck }

        let configuration: SandboxPurchaseConfiguration?
        @Published private(set) var isBusy = false
        @Published private(set) var result =
            "Ready. Run on a device with StoreKit Configuration set to None."

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
                action == .buy
                ? "Opening Apple Sandbox purchase…" : "Rechecking the latest purchase…"
            defer { isBusy = false }

            do {
                let evidence: VerificationResult<StoreKit.Transaction>
                switch action {
                case .buy:
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

                guard case .verified(let transaction) = evidence else {
                    throw SandboxPurchaseError(
                        message:
                            "StoreKit could not verify this transaction. Nothing was sent to the backend."
                    )
                }
                try configuration.validate(
                    environment: transaction.environment, productID: transaction.productID)
                let client = SandboxSubscriptionClient(configuration: configuration)
                let entitlement = try await client.verify(
                    signedTransactionInfo: evidence.jwsRepresentation)
                // Leave failed verifications unfinished so Recheck can retry without another purchase.
                await transaction.finish()
                result = entitlement.diagnosticSummary
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

        init(environment: [String: String]) throws {
            guard let rawURL = environment["SANDBOX_API_URL"],
                let url = URL(string: rawURL), url.scheme == "https",
                let host = url.host, !host.isEmpty,
                url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                url.port == nil || url.port == 443,
                let product = environment["SANDBOX_PRODUCT_ID"]?.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                !product.isEmpty
            else {
                throw SandboxPurchaseError(
                    message:
                        "Set SANDBOX_API_URL (HTTPS) and SANDBOX_PRODUCT_ID in an unshared Xcode Run scheme, then run again."
                )
            }
            baseURL = url
            productID = product
        }

        func validate(environment: AppStore.Environment, productID: String) throws {
            guard environment == .sandbox, productID == self.productID else {
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

    nonisolated struct SandboxSubscriptionClient {
        let configuration: SandboxPurchaseConfiguration
        private let session: URLSession

        init(
            configuration: SandboxPurchaseConfiguration,
            session: URLSession = ProviderNetworkSession.make()
        ) {
            self.configuration = configuration
            self.session = session
        }

        func verify(signedTransactionInfo: String) async throws -> SandboxEntitlement {
            struct Body: Encodable { let signedTransactionInfo: String }
            var request = URLRequest(
                url: configuration.baseURL.appending(path: "v1/subscriptions/verify"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                Body(signedTransactionInfo: signedTransactionInfo))
            let (data, response) = try await session.data(
                for: request, delegate: RejectPurchaseRedirects())
            guard let http = response as? HTTPURLResponse else {
                throw SandboxPurchaseError(message: "Backend returned a non-HTTP response.")
            }
            guard http.statusCode == 200 else {
                let hint: String
                switch http.statusCode {
                case 401:
                    hint =
                        "Apple transaction rejected. Check the backend's Sandbox product and bundle configuration."
                case 404:
                    hint =
                        "Verification route missing. Deploy Step 3 to Sandbox and check the API URL."
                case 503:
                    hint =
                        "Verification unavailable. Check the Sandbox Apple secret and backend logs."
                default: hint = "Check the Sandbox deployment and backend logs."
                }
                // Do not display arbitrary response bodies, which could echo signed purchase evidence.
                throw SandboxPurchaseError(
                    message: "HTTP \(http.statusCode). \(hint) Retry with Recheck purchase.")
            }
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
    }

    nonisolated struct SandboxEntitlement: Decodable {
        struct Period: Decodable {
            let id: String
            let kind: String
            let startsAt: String
            let expiresAt: String
        }
        let subscriptionId: String
        let environment: String
        let productId: String
        let active: Bool
        let status: String
        let accessUntil: String
        let willRenew: Bool
        let period: Period
        let verifiedAt: String

        var diagnosticSummary: String {
            """
            Backend verified · \(environment)
            Status: \(status) · active: \(active)
            Period: \(period.kind) · renews: \(willRenew)
            Access until: \(accessUntil)
            Period start: \(period.startsAt)
            Period end: \(period.expiresAt)
            Verified at: \(verifiedAt)
            Subscription ID: \(subscriptionId)
            Period ID: \(period.id)
            """
        }
    }

    private nonisolated final class RejectPurchaseRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
#endif
