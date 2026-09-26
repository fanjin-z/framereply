import Combine
import Foundation
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
    var errorDescription: String? { message }
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
        let entitlement = try await verify(signedTransactionInfo: evidence.jwsRepresentation)
        // A failed backend verification leaves the transaction unfinished for recovery.
        await transaction.finish()
        return entitlement
    }

    func credential(serviceSubscriptionId: String) async throws -> ManagedAICredential {
        let data = try await post(
            operation: .credential, body: subscriptionBody(serviceSubscriptionId))
        guard let credential = try? JSONDecoder().decode(ManagedAICredential.self, from: data),
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
            let retry = operation == .subscription ? " Use Restore Purchases." : ""
            throw SubscriptionClientError(message: error.diagnosticSummary + retry)
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
    private var processing = Set<UInt64>()

    func start() {
        guard updates == nil else { return }
        updates = Task {
            for await evidence in Transaction.updates { await process(evidence) }
        }
        unfinished = Task {
            for await evidence in Transaction.unfinished { await process(evidence) }
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
            lastResult = "Transaction update could not be verified. Use Restore Purchases."
        }
    }
}
