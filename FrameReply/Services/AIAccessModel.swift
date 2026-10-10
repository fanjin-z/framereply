import Combine
import Foundation
import StoreKit

nonisolated enum AIAccessPresentation {
    enum UsageLevel: Equatable {
        case available, low, exhausted
    }

    static func remainingFraction(_ usage: SubscriptionUsage) -> Double? {
        guard !usage.stale, usage.budgetMicrousd > 0,
            let remaining = usage.remainingMicrousd,
            ["available", "exhausted"].contains(usage.availability)
        else { return nil }
        return min(1, max(0, Double(remaining) / Double(usage.budgetMicrousd)))
    }

    static func usageLevel(_ fraction: Double) -> UsageLevel {
        if fraction <= 0 { return .exhausted }
        return fraction <= 0.2 ? .low : .available
    }

    static func duration(
        value: Int, unit: Product.SubscriptionPeriod.Unit, count: Int = 1,
        locale: Locale = LocalizationContext.current.locale
    ) -> String? {
        guard value > 0, count > 0 else { return nil }
        let (total, overflow) = value.multipliedReportingOverflow(by: count)
        guard !overflow else { return nil }
        var components = DateComponents()
        let allowed: NSCalendar.Unit
        switch unit {
        case .day:
            components.day = total
            allowed = .day
        case .week:
            components.weekOfMonth = total
            allowed = .weekOfMonth
        case .month:
            components.month = total
            allowed = .month
        case .year:
            components.year = total
            allowed = .year
        @unknown default: return nil
        }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = allowed
        formatter.unitsStyle = .full
        return formatter.string(from: components)
    }

    static func billingPeriod(
        value: Int, unit: Product.SubscriptionPeriod.Unit,
        locale: Locale = LocalizationContext.current.locale
    ) -> String? {
        guard value == 1 else { return duration(value: value, unit: unit, locale: locale) }
        switch unit {
        case .day: return String(localized: "day", locale: locale)
        case .week: return String(localized: "week", locale: locale)
        case .month: return String(localized: "month", locale: locale)
        case .year: return String(localized: "year", locale: locale)
        @unknown default: return nil
        }
    }

    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

@MainActor
final class AIAccessModel: ObservableObject {
    static let usageDidChange = Notification.Name("FrameReply.managedAIUsageDidChange")

    @Published private(set) var product: Product?
    enum ProductAvailability {
        case loading, available, notOffered, failed
    }

    @Published private(set) var productAvailability: ProductAvailability = .loading
    @Published private(set) var trialDuration: String?

    var billingPeriod: String? {
        guard let period = product?.subscription?.subscriptionPeriod else { return nil }
        return AIAccessPresentation.billingPeriod(value: period.value, unit: period.unit)
    }
    @Published private(set) var entitlement: SubscriptionEntitlement?
    @Published private(set) var usage: SubscriptionUsage?
    @Published private(set) var usageIssue: String?
    @Published private(set) var notice: String?
    @Published private(set) var isBusy = false
    @Published private(set) var statusUnavailable = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingConfiguration = false
    @Published private(set) var configuration: SubscriptionConfiguration?

    private var client: SubscriptionClient?
    private let authentication: (any AppAttestAuthenticating)?
    private let now: () -> Date
    private let latestEntitlement: (SubscriptionClient) async throws -> SubscriptionEntitlement?
    private var hasLoadedStatus = false
    private var statusCheckedAt: Date?
    private var productsCheckedAt: Date?
    private var usageCheckedAt: Date?
    private var entitlementRevision = 0
    private var usageRevision = 0
    private var productRevision = 0
    private var configurationTask: Task<Bool, Never>?
    private var statusTask: Task<Bool, Never>?
    private var productTask: Task<Void, Never>?
    private var usageTask: Task<Void, Never>?
    private var storefrontTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    var hasActiveSubscription: Bool {
        guard entitlement?.active == true,
            let accessEnd = entitlement.flatMap({ AIAccessPresentation.date($0.accessUntil) })
        else { return false }
        return accessEnd > now() && !statusUnavailable
    }

    var isInitiallyLoading: Bool {
        isLoadingConfiguration || (!hasLoadedStatus && isRefreshing)
            || (configuration != nil && !hasActiveSubscription && productAvailability == .loading)
    }

    init(
        configuration: SubscriptionConfiguration? = nil,
        authentication: (any AppAttestAuthenticating)? = nil,
        now: @escaping () -> Date = Date.init,
        latestEntitlement: @escaping (SubscriptionClient) async throws -> SubscriptionEntitlement? =
            {
                client in
                // Keep the latest evidence so the backend can report expiry and revocation too.
                guard let evidence = await Transaction.latest(for: client.configuration.productID)
                else { return nil }
                return try await client.verifyAndFinish(evidence)
            }
    ) {
        self.configuration = configuration
        self.authentication = authentication
        self.now = now
        self.latestEntitlement = latestEntitlement
        client = configuration.map {
            SubscriptionClient(configuration: $0, authentication: authentication)
        }
    }

    deinit {
        storefrontTask?.cancel()
        expiryTask?.cancel()
    }

    func start() async {
        guard storefrontTask == nil else { return }
        SubscriptionTransactionObserver.shared.$entitlement
            .compactMap { $0 }
            .sink { [weak self] verified in
                self?.acceptVerifiedEntitlement(verified)
                Task { [weak self] in await self?.refreshUsageIfNeeded() }
            }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Self.usageDidChange)
            .sink { [weak self] _ in self?.invalidateUsage() }
            .store(in: &subscriptions)
        storefrontTask = Task { [weak self] in
            for await _ in Storefront.updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.productRevision += 1
                self.productsCheckedAt = nil
                self.product = nil
                self.trialDuration = nil
                self.productAvailability = .loading
                await self.loadProductsIfNeeded(force: true)
                _ = await self.refreshStatusIfNeeded(force: true)
                await self.refreshUsageIfNeeded()
            }
        }
        await load()
    }

    /// Navigation and foreground refreshes retain confirmed data and do not block the card.
    func load() async {
        guard !isBusy, await configure() else { return }
        _ = await refreshStatusIfNeeded()
        await loadProductsIfNeeded()
        await refreshUsageIfNeeded()
    }

    private func configure(refreshAppTransaction: Bool = false) async -> Bool {
        if configuration != nil { return true }
        if let configurationTask {
            return await configurationTask.value
        }
        isLoadingConfiguration = true
        let task = Task { () -> Bool in
            defer { configurationTask = nil }
            let resolved: SubscriptionConfiguration?
            do {
                resolved = try await SubscriptionConfiguration.load(
                    refreshAppTransaction: refreshAppTransaction)
            } catch {
                SubscriptionDiagnostics.record(error, operation: "Subscription configuration")
                resolved = nil
            }
            configuration = resolved
            client = resolved.map {
                SubscriptionClient(configuration: $0, authentication: authentication)
            }
            isLoadingConfiguration = false
            if let verified = SubscriptionTransactionObserver.shared.entitlement {
                acceptVerifiedEntitlement(verified)
            }
            return resolved != nil
        }
        configurationTask = task
        return await task.value
    }

    private func loadProductsIfNeeded(force: Bool = false) async {
        if let productTask {
            await productTask.value
            if force { await loadProductsIfNeeded(force: true) }
            return
        }
        guard let configuration, force || !isFresh(productsCheckedAt, for: 300) else { return }
        productsCheckedAt = now()
        let revision = productRevision
        let task = Task {
            await fetchProduct(configuration: configuration, revision: revision)
            productTask = nil
        }
        productTask = task
        await task.value
    }

    private func fetchProduct(configuration: SubscriptionConfiguration, revision: Int) async {
        do {
            let fetched = try await Product.products(for: [configuration.productID]).first
            var trial: String?
            if let fetched, fetched.type == .autoRenewable,
                let subscription = fetched.subscription
            {
                if let offer = subscription.introductoryOffer,
                    offer.paymentMode == .freeTrial,
                    await subscription.isEligibleForIntroOffer
                {
                    trial = AIAccessPresentation.duration(
                        value: offer.period.value, unit: offer.period.unit, count: offer.periodCount
                    )
                }
                guard revision == productRevision else { return }
                product = fetched
                trialDuration = trial
                productAvailability = .available
            } else {
                guard revision == productRevision else { return }
                product = nil
                trialDuration = nil
                productAvailability = .notOffered
            }
        } catch {
            if revision == productRevision && product == nil { productAvailability = .failed }
        }
    }

    /// Explicit refreshes bypass freshness and show progress, without clearing valid snapshots.
    func refresh(refreshAppTransaction: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        notice = nil
        guard await configure(refreshAppTransaction: refreshAppTransaction) else { return }
        await loadProductsIfNeeded(force: true)
        if !(await refreshStatusIfNeeded(force: true)) {
            notice = String(localized: "Couldn’t check subscription status. Try again.")
        }
        await refreshUsageIfNeeded(force: true)
    }

    // True only when this explicit action verifies active access. An existing
    // entitlement must not turn cancellation, pending, or failure into activation.
    func purchase() async -> Bool {
        guard !isBusy, let product, let client else { return false }
        isBusy = true
        defer { isBusy = false }
        notice = nil

        do {
            // Fail before Apple's payment sheet if this device cannot use the backend.
            try await client.checkAuthentication()
        } catch {
            notice = String(
                localized: "AI Access is unavailable right now. No purchase was started.")
            return false
        }

        do {
            switch try await product.purchase() {
            case .success(let evidence):
                let verified = try await client.verifyAndFinish(evidence)
                acceptVerifiedEntitlement(verified)
                await refreshUsageIfNeeded(force: true)
                notice = String(localized: "Subscription verified with FrameReply.")
                return verified.active
            case .pending:
                notice = String(localized: "Purchase pending. Refresh after Apple approves it.")
            case .userCancelled:
                break
            @unknown default:
                notice = String(localized: "Purchase status is unknown. Use Restore Purchases.")
            }
        } catch {
            notice = String(
                localized:
                    "Couldn’t verify the purchase. If Apple completed it, use Restore Purchases."
            )
        }
        return false
    }

    func restore() async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        notice = nil

        do {
            // StoreKit prompts for Apple Account authentication, so only call after a tap.
            try await AppStore.sync()
            guard await refreshStatusIfNeeded(force: true) else {
                notice = String(localized: "Couldn’t restore purchases. Try again later.")
                return false
            }
            await refreshUsageIfNeeded(force: true)
            notice =
                entitlement?.active == true
                ? String(localized: "Subscription restored.")
                : String(localized: "No active subscription found for this Apple Account.")
            return entitlement?.active == true
        } catch {
            notice = String(localized: "Couldn’t restore purchases. Try again later.")
        }
        return false
    }

    @discardableResult
    func refreshStatusIfNeeded(force: Bool = false) async -> Bool {
        if let statusTask {
            let result = await statusTask.value
            if force { return await refreshStatusIfNeeded(force: true) }
            return result
        }
        guard let client else { return false }
        let accessEnd = entitlement.flatMap { AIAccessPresentation.date($0.accessUntil) }
        let crossedAccessEnd =
            accessEnd.map { accessEnd in
                accessEnd <= now() && (statusCheckedAt.map { $0 < accessEnd } ?? true)
            } ?? false
        guard force || crossedAccessEnd || !isFresh(statusCheckedAt, for: 300) else {
            return !statusUnavailable
        }
        if entitlement?.active == true && accessEnd.map({ $0 <= now() }) == true {
            statusUnavailable = true
        }
        statusCheckedAt = now()
        isRefreshing = true
        let revision = entitlementRevision
        let task = Task { () -> Bool in
            defer {
                statusTask = nil
                isRefreshing = false
            }
            do {
                let verified = try await latestEntitlement(client)
                guard revision == entitlementRevision else { return true }
                if let verified {
                    acceptVerifiedEntitlement(verified)
                } else {
                    entitlementRevision += 1
                    entitlement = nil
                    usage = nil
                    invalidateUsage()
                    statusUnavailable = false
                    hasLoadedStatus = true
                    if !isBusy { notice = nil }
                    expiryTask?.cancel()
                }
                return true
            } catch {
                SubscriptionDiagnostics.record(error, operation: "Subscription status verification")
                guard revision == entitlementRevision else { return true }
                if !hasLoadedStatus || (entitlement?.active == true && !hasActiveSubscription) {
                    statusUnavailable = true
                    notice = String(
                        localized: "Couldn’t check subscription status. Try Refresh Status.")
                }
                return false
            }
        }
        statusTask = task
        return await task.value
    }

    func acceptVerifiedEntitlement(_ verified: SubscriptionEntitlement) {
        guard let configuration,
            verified.environment == configuration.entitlementEnvironment,
            verified.productId == configuration.productID
        else { return }
        entitlementRevision += 1
        if entitlement?.active != verified.active {
            productsCheckedAt = nil
            trialDuration = nil
        }
        if entitlement?.serviceSubscriptionId != verified.serviceSubscriptionId
            || entitlement?.period.id != verified.period.id
            || entitlement?.period.kind != verified.period.kind || !verified.active
        {
            usage = nil
            usageIssue = nil
            invalidateUsage()
        }
        entitlement = verified
        statusUnavailable =
            verified.active
            && AIAccessPresentation.date(verified.accessUntil).map({ $0 <= now() }) != false
        hasLoadedStatus = true
        if !isBusy { notice = nil }
        statusCheckedAt = now()
        scheduleAccessEndRefresh()
    }

    func invalidateUsage() {
        usageRevision += 1
        usageCheckedAt = nil
    }

    func refreshUsageIfNeeded(force: Bool = false) async {
        if let usageTask {
            await usageTask.value
            await refreshUsageIfNeeded(force: force)
            return
        }
        guard hasActiveSubscription, let verified = entitlement, let client,
            force || !isFresh(usageCheckedAt, for: 60)
        else { return }
        usageCheckedAt = now()
        let revision = usageRevision
        let task = Task {
            defer { usageTask = nil }
            do {
                let current = try await client.usage(
                    serviceSubscriptionId: verified.serviceSubscriptionId)
                guard current.periodId == verified.period.id,
                    current.kind == verified.period.kind
                else { throw SubscriptionClientError(message: "Allowance period mismatch.") }
                guard revision == usageRevision else { return }
                usage = current
                usageIssue = nil
            } catch {
                guard revision == usageRevision else { return }
                usageIssue = String(localized: "Couldn’t load your current AI allowance.")
            }
        }
        usageTask = task
        await task.value
    }

    private func isFresh(_ checkedAt: Date?, for interval: TimeInterval) -> Bool {
        guard let checkedAt else { return false }
        let age = now().timeIntervalSince(checkedAt)
        return age >= 0 && age < interval
    }

    private func scheduleAccessEndRefresh() {
        expiryTask?.cancel()
        guard storefrontTask != nil, hasActiveSubscription,
            let accessEnd = entitlement.flatMap({ AIAccessPresentation.date($0.accessUntil) })
        else { return }
        let delay = accessEnd.timeIntervalSince(now())
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            _ = await self?.refreshStatusIfNeeded(force: true)
            await self?.refreshUsageIfNeeded()
        }
    }
}
