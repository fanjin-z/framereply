import Combine
import Foundation
import OSLog
import StoreKit

/// Public routing configuration. Release selects its backend from verified Apple evidence.
nonisolated struct SubscriptionConfiguration {
    let baseURL: URL
    let productID: String
    let appAttestEnvironment: String
    let storeEnvironment: AppStore.Environment

    static func load(bundle: Bundle = .main, refreshAppTransaction: Bool = false) async throws
        -> Self
    {
        let mode =
            bundle.object(forInfoDictionaryKey: "SubscriptionStoreEnvironment") as? String ?? ""
        var environment: AppStore.Environment?
        if mode == "Automatic" {
            // Refresh may prompt for Apple Account authentication; only a user tap enables it.
            let evidence =
                try await (refreshAppTransaction ? AppTransaction.refresh() : AppTransaction.shared)
            guard case .verified(let transaction) = evidence else {
                throw SubscriptionClientError(
                    message: "Apple could not verify the app environment.")
            }
            environment = transaction.environment
        }
        return try Self(
            apiURL: bundle.object(forInfoDictionaryKey: "SubscriptionAPIURL") as? String ?? "",
            sandboxAPIURL: bundle.object(forInfoDictionaryKey: "SubscriptionSandboxAPIURL")
                as? String ?? "",
            productID: bundle.object(forInfoDictionaryKey: "SubscriptionProductID") as? String
                ?? "",
            appAttestEnvironment: bundle.object(forInfoDictionaryKey: "AppAttestEnvironment")
                as? String ?? "",
            storeEnvironment: mode,
            verifiedAppEnvironment: environment
        )
    }

    init(
        apiURL: String, sandboxAPIURL: String = "", productID: String, appAttestEnvironment: String,
        storeEnvironment: String = "Sandbox", verifiedAppEnvironment: AppStore.Environment? = nil
    ) throws {
        var apiURL = apiURL
        var storeEnvironment = storeEnvironment
        if storeEnvironment == "Automatic" {
            // Never infer routing from a build flag, receipt filename, or an unverified JWS.
            guard appAttestEnvironment == "production", let verifiedAppEnvironment,
                verifiedAppEnvironment == .sandbox || verifiedAppEnvironment == .production
            else {
                throw SubscriptionClientError(
                    message: "Apple subscription environment is unavailable.")
            }
            // Validate both routes even if only one will be used on this installation.
            let sandbox = try Self(
                apiURL: sandboxAPIURL, productID: productID,
                appAttestEnvironment: appAttestEnvironment, storeEnvironment: "Sandbox")
            let production = try Self(
                apiURL: apiURL, productID: productID,
                appAttestEnvironment: appAttestEnvironment, storeEnvironment: "Production")
            guard sandbox.baseURL != production.baseURL else {
                throw SubscriptionClientError(
                    message: "Subscription environments must use separate backends.")
            }
            storeEnvironment = verifiedAppEnvironment == .sandbox ? "Sandbox" : "Production"
            if verifiedAppEnvironment == .sandbox { apiURL = sandboxAPIURL }
        }
        guard ["development", "production"].contains(appAttestEnvironment),
            ["Sandbox", "Production"].contains(storeEnvironment),
            let url = URL(string: apiURL), url.scheme == "https",
            let host = url.host, !host.isEmpty,
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
            url.port == nil || url.port == 443,
            url.path.isEmpty || url.path == "/"
        else {
            throw SubscriptionClientError(
                message: "Subscription configuration is unavailable in this build.")
        }
        let productID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !productID.isEmpty else {
            throw SubscriptionClientError(
                message: "Subscription product is not configured.")
        }
        baseURL = url
        self.productID = productID
        self.appAttestEnvironment = appAttestEnvironment
        self.storeEnvironment = storeEnvironment == "Sandbox" ? .sandbox : .production
    }

    func validate(environment: AppStore.Environment, productID: String) throws {
        guard environment == storeEnvironment, productID == self.productID else {
            throw SubscriptionClientError(
                message: "Only the configured Apple subscription can be verified.")
        }
    }

    var entitlementEnvironment: String {
        storeEnvironment == .sandbox ? "Sandbox" : "Production"
    }
}

nonisolated struct SubscriptionClientError: LocalizedError {
    let message: String
    let authenticationError: AppAttestClientError?

    init(message: String, authenticationError: AppAttestClientError? = nil) {
        self.message = message
        self.authenticationError = authenticationError
    }

    var errorDescription: String? { message }
}

nonisolated enum SubscriptionDiagnostics {
    private static let logger = Logger(
        subsystem: "com.gigabeyond.framereply", category: "Subscription")

    static func record(_ error: Error, operation: String) {
        if let cause = (error as? SubscriptionClientError)?.authenticationError
            ?? (error as? AppAttestClientError)
        {
            let summary: String
            if case .backend(let status, let code) = cause {
                // Only known protocol codes are public; never echo arbitrary response content.
                let safeCode =
                    code.flatMap {
                        AppAttestClientError.knownBackendCodes.contains($0) ? $0 : nil
                    } ?? "UNKNOWN"
                summary = "Backend HTTP \(status) (\(safeCode))"
            } else {
                summary = cause.diagnosticSummary
            }
            logger.error("\(operation, privacy: .public) failed: \(summary, privacy: .public)")
            return
        }
        // Error descriptions may contain device or purchase details. Keep them private;
        // never log the signed transaction, receipt, request body, or credentials.
        logger.error(
            "\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .private)"
        )
    }
}

nonisolated struct SubscriptionEntitlement: Decodable {
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
}

nonisolated struct ManagedAICredential: Decodable {
    let consentVersion: String
    let aiProvider: String
    let model: String
    let responseModel: String
    let apiKey: String
    let expiresAt: String
}

nonisolated struct SubscriptionUsage: Decodable {
    let serviceSubscriptionId: String
    let periodId: String
    let kind: String
    let currency: String
    let budgetMicrousd: Int
    let usedMicrousd: Int
    let remainingMicrousd: Int?
    let expiresAt: String
    let availability: String
    let usageAsOf: String?
    let stale: Bool
}

@MainActor
struct SubscriptionClient {
    let configuration: SubscriptionConfiguration
    private let authentication: any AppAttestAuthenticating

    init(
        configuration: SubscriptionConfiguration,
        authentication: (any AppAttestAuthenticating)? = nil
    ) {
        self.configuration = configuration
        self.authentication =
            authentication
            ?? AppAttestClient.shared(
                baseURL: configuration.baseURL,
                environment: configuration.appAttestEnvironment)
    }

    func checkAuthentication() async throws {
        let data = try await post(operation: .status, body: Data("{}".utf8))
        struct Status: Decodable { let authenticated: Bool }
        guard (try? JSONDecoder().decode(Status.self, from: data).authenticated) == true else {
            throw SubscriptionClientError(message: "Backend authentication response is malformed.")
        }
    }

    func verify(signedTransactionInfo: String) async throws -> SubscriptionEntitlement {
        struct Body: Encodable { let signedTransactionInfo: String }
        let body = try JSONEncoder().encode(Body(signedTransactionInfo: signedTransactionInfo))
        let data = try await post(operation: .subscription, body: body)
        struct Response: Decodable { let entitlement: SubscriptionEntitlement }
        guard let entitlement = try? JSONDecoder().decode(Response.self, from: data).entitlement,
            entitlement.environment == configuration.entitlementEnvironment,
            entitlement.productId == configuration.productID,
            !entitlement.serviceSubscriptionId.isEmpty
        else {
            throw SubscriptionClientError(
                message:
                    "Backend subscription response is invalid. The purchase remains unfinished; use Restore Purchases."
            )
        }
        return entitlement
    }

    func verifyAndFinish(_ evidence: VerificationResult<Transaction>) async throws
        -> SubscriptionEntitlement
    {
        guard case .verified(let transaction) = evidence else {
            throw SubscriptionClientError(message: "StoreKit could not verify this transaction.")
        }
        try configuration.validate(
            environment: transaction.environment, productID: transaction.productID)
        let key = SubscriptionVerificationCoordinator.Key(
            configuration: configuration, transactionID: transaction.id)
        return try await SubscriptionVerificationCoordinator.shared.verify(key: key) {
            let entitlement = try await verify(signedTransactionInfo: evidence.jwsRepresentation)
            // Finish only after server verification. Failed attempts remain recoverable.
            await transaction.finish()
            return entitlement
        }
    }

    func aiConsent() async throws -> ManagedAIConsent {
        let data = try await post(operation: .configuration, body: Data("{}".utf8))
        struct Configuration: Decodable { let consent: ManagedAIConsent }
        guard let consent = try? JSONDecoder().decode(Configuration.self, from: data).consent,
            consent.isValid
        else {
            throw SubscriptionClientError(
                message: String(localized: AppStrings.Provider.managedConsentUnavailable))
        }
        return consent
    }

    func credential(serviceSubscriptionId: String, consent: ManagedAIConsent) async throws
        -> ManagedAICredential
    {
        guard consent.isValid, !serviceSubscriptionId.isEmpty else {
            throw ProviderConnectionError.dataConsentRequired
        }
        struct Body: Encodable {
            let serviceSubscriptionId: String
            let consentVersion: String
        }
        let data = try await post(
            operation: .credential,
            body: JSONEncoder().encode(
                Body(serviceSubscriptionId: serviceSubscriptionId, consentVersion: consent.version))
        )
        guard let credential = try? JSONDecoder().decode(ManagedAICredential.self, from: data),
            credential.consentVersion == consent.version,
            !credential.aiProvider.isEmpty, !credential.model.isEmpty,
            !credential.apiKey.isEmpty, !credential.expiresAt.isEmpty
        else {
            throw SubscriptionClientError(message: "Backend credential response is invalid.")
        }
        return credential
    }

    func usage(serviceSubscriptionId: String) async throws -> SubscriptionUsage {
        let data = try await post(operation: .usage, body: subscriptionBody(serviceSubscriptionId))
        guard let usage = try? JSONDecoder().decode(SubscriptionUsage.self, from: data),
            usage.serviceSubscriptionId == serviceSubscriptionId,
            usage.currency == "USD", usage.budgetMicrousd >= 0, usage.usedMicrousd >= 0,
            usage.remainingMicrousd.map({ $0 >= 0 }) ?? true
        else {
            throw SubscriptionClientError(message: "Backend usage response is invalid.")
        }
        return usage
    }

    private func subscriptionBody(_ serviceSubscriptionId: String) throws -> Data {
        guard !serviceSubscriptionId.isEmpty else {
            throw SubscriptionClientError(message: "Verify a subscription first.")
        }
        struct Body: Encodable { let serviceSubscriptionId: String }
        return try JSONEncoder().encode(Body(serviceSubscriptionId: serviceSubscriptionId))
    }

    private func post(operation: AppAttestOperation, body: Data) async throws -> Data {
        do {
            return try await authentication.post(operation: operation, body: body)
        } catch let error as AppAttestClientError {
            if case .backend(_, let code) = error, code == "AI_CONSENT_REQUIRED" {
                throw ProviderConnectionError.dataConsentRequired
            }
            let message: String
            switch error {
            case .backend(_, code: "AI_ALLOWANCE_EXHAUSTED"):
                message = String(localized: "Your AI allowance is used up for this period.")
            case .backend(_, code: "AI_ACCESS_INACTIVE"):
                message = String(localized: "Your AI Access subscription is inactive.")
            default:
                message = String(localized: "FrameReply AI is temporarily unavailable. Try again.")
            }
            throw SubscriptionClientError(
                message: message, authenticationError: error)
        }
    }
}

/// Purchase, restore and StoreKit observers share retries for the same transaction.
@MainActor
final class SubscriptionVerificationCoordinator {
    static let shared = SubscriptionVerificationCoordinator()

    struct Key: Hashable {
        let backend: URL
        let appAttestEnvironment: String
        let storeEnvironment: String
        let productID: String
        let transactionID: UInt64

        init(configuration: SubscriptionConfiguration, transactionID: UInt64) {
            backend = configuration.baseURL
            appAttestEnvironment = configuration.appAttestEnvironment
            storeEnvironment = configuration.entitlementEnvironment
            productID = configuration.productID
            self.transactionID = transactionID
        }
    }

    private var pending: [Key: Task<SubscriptionEntitlement, Error>] = [:]
    private let wait: (UInt64) async throws -> Void

    init(
        wait: @escaping (UInt64) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.wait = wait
    }

    func verify(
        key: Key, operation: @escaping @MainActor () async throws -> SubscriptionEntitlement
    ) async throws -> SubscriptionEntitlement {
        // The shared task survives cancellation of one caller so other observers can recover it.
        if let task = pending[key] { return try await task.value }
        let task = Task {
            for attempt in 0..<3 {
                do {
                    return try await operation()
                } catch {
                    guard attempt < 2, Self.isRetryable(error) else { throw error }
                    try await wait(UInt64(2 << attempt))
                }
            }
            throw CancellationError()
        }
        pending[key] = task
        defer { pending[key] = nil }
        return try await task.value
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard
            let cause = (error as? SubscriptionClientError)?.authenticationError
                ?? (error as? AppAttestClientError)
        else { return false }
        switch cause {
        case .network:
            return true
        case .backend(let status, let code):
            // Invalid evidence, denied authentication and operator recovery are not transient.
            return status >= 500
                && (code == "SUBSCRIPTION_UNAVAILABLE" || code == "INTERNAL_ERROR" || code == nil)
        default:
            return false
        }
    }
}

@MainActor
final class SubscriptionTransactionObserver: ObservableObject {
    static let shared = SubscriptionTransactionObserver()

    @Published private(set) var lastResult: String?
    @Published private(set) var entitlement: SubscriptionEntitlement?
    private var updates: Task<Void, Never>?
    private var unfinished: Task<Void, Never>?
    private var statusUpdates: Task<Void, Never>?
    private var processing = Set<UInt64>()

    func start() {
        guard updates == nil else { return }
        updates = Task {
            for await evidence in Transaction.updates { await process(evidence) }
        }
        unfinished = Task {
            for await evidence in Transaction.unfinished { await process(evidence) }
        }
        statusUpdates = Task {
            for await status in Product.SubscriptionInfo.Status.updates {
                await process(status.transaction)
            }
        }
    }

    private func process(_ evidence: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = evidence else {
            lastResult = "StoreKit delivered an unverified transaction. Use Restore Purchases."
            return
        }
        guard let configuration = try? await SubscriptionConfiguration.load(),
            transaction.productID == configuration.productID,
            transaction.environment == configuration.storeEnvironment,
            processing.insert(transaction.id).inserted
        else { return }
        defer { processing.remove(transaction.id) }

        do {
            let verified = try await SubscriptionClient(configuration: configuration)
                .verifyAndFinish(evidence)
            entitlement = verified
            lastResult = "Transaction update verified · \(verified.status)."
        } catch {
            // StoreKit retains an unfinished transaction. Do not log its signed evidence.
            SubscriptionDiagnostics.record(error, operation: "Transaction update verification")
            lastResult = "Transaction update could not be verified. Use Restore Purchases."
        }
    }
}
