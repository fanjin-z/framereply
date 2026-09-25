#if DEBUG
    import Combine
    import Foundation
    import StoreKit

    @MainActor
    final class SandboxPurchaseProbe: ObservableObject {
        enum Action { case authenticate, buy, recheck }

        let configuration: SubscriptionConfiguration?
        @Published private(set) var isBusy = false
        @Published private(set) var result =
            "Start with Test authentication on a physical iPhone. Purchases also require StoreKit Configuration set to None."

        init() {
            do {
                configuration = try SubscriptionConfiguration.load()
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
                let client = SubscriptionClient(configuration: configuration)
                if action == .authenticate {
                    try await client.checkAuthentication()
                    result =
                        "App Attest authenticated · \(configuration.appAttestEnvironment). No purchase was made and no AI access was granted."
                    return
                }
                guard !configuration.productID.isEmpty else {
                    throw SubscriptionClientError(
                        message:
                            "The Sandbox subscription product is not configured in this build.")
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
                        throw SubscriptionClientError(
                            message:
                                "An Apple Sandbox app transaction is required. Run a development build with StoreKit Configuration set to None."
                        )
                    }
                    guard
                        let product = try await Product.products(for: [configuration.productID])
                            .first,
                        product.type == .autoRenewable
                    else {
                        throw SubscriptionClientError(
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
                        throw SubscriptionClientError(
                            message: "Unexpected StoreKit purchase result. Try Recheck purchase.")
                    }
                case .recheck:
                    // Current entitlements omit expired purchases, which this probe also needs to test.
                    guard
                        let latest = await StoreKit.Transaction.latest(for: configuration.productID)
                    else {
                        throw SubscriptionClientError(
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
            } catch let error as SubscriptionClientError {
                result = error.message
            } catch {
                // StoreKit/network errors may contain sensitive evidence; never print their payloads.
                let code = (error as NSError).code
                result =
                    "Apple or network operation failed (code \(code)). Check Sandbox sign-in and connectivity. If the purchase completed, use Recheck purchase; otherwise try Buy and verify again."
            }
        }
    }

#endif
