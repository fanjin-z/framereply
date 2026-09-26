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

    private let configuration: SubscriptionConfiguration
    private let client: SubscriptionClient

    init(configuration: SubscriptionConfiguration) {
        self.configuration = configuration
        client = SubscriptionClient(configuration: configuration)
    }

    func load() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        notice = nil
        product = nil
        trialDuration = nil
        productAvailability = .loading
        do {
            let fetched = try await Product.products(for: [configuration.productID]).first
            if let fetched, fetched.type == .autoRenewable,
                let subscription = fetched.subscription
            {
                product = fetched
                if let offer = subscription.introductoryOffer,
                    offer.paymentMode == .freeTrial,
                    await subscription.isEligibleForIntroOffer
                {
                    trialDuration = AIAccessPresentation.duration(
                        value: offer.period.value, unit: offer.period.unit, count: offer.periodCount
                    )
                }
                productAvailability = .available
            } else {
                productAvailability = .notOffered
            }
        } catch {
            productAvailability = .failed
        }

        do { try await refreshStatus() } catch {
            notice = String(localized: "Couldn’t check subscription status. Try Refresh Status.")
        }
    }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        notice = nil
        do { try await refreshStatus() } catch {
            notice = String(localized: "Couldn’t check subscription status. Try again.")
        }
    }

    func purchase() async {
        guard !isBusy, let product else { return }
        isBusy = true
        defer { isBusy = false }
        notice = nil

        do {
            // Fail before Apple's payment sheet if this device cannot use the backend.
            try await client.checkAuthentication()
        } catch {
            notice = String(
                localized: "AI Access is unavailable right now. No purchase was started.")
            return
        }

        do {
            switch try await product.purchase() {
            case .success(let evidence):
                let verified = try await client.verifyAndFinish(evidence)
                entitlement = verified
                statusUnavailable = false
                await loadUsage(for: verified)
                notice = String(localized: "Subscription verified with FrameReply.")
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
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        notice = nil

        do {
            // StoreKit prompts for Apple Account authentication, so only call after a tap.
            try await AppStore.sync()
            try await refreshStatus()
            notice =
                entitlement?.active == true
                ? String(localized: "Subscription restored.")
                : String(localized: "No active subscription found for this Apple Account.")
        } catch {
            notice = String(localized: "Couldn’t restore purchases. Try again later.")
        }
    }

    private func refreshStatus() async throws {
        // The latest signed transaction also lets the backend report expiry or revocation.
        statusUnavailable = true
        entitlement = nil
        usage = nil
        usageIssue = nil
        guard let evidence = await Transaction.latest(for: configuration.productID) else {
            statusUnavailable = false
            return
        }
        let verified = try await client.verifyAndFinish(evidence)
        entitlement = verified
        statusUnavailable = false
        await loadUsage(for: verified)
    }

    private func loadUsage(for verified: SubscriptionEntitlement) async {
        usage = nil
        usageIssue = nil
        guard verified.active else { return }
        do {
            let current = try await client.usage(
                serviceSubscriptionId: verified.serviceSubscriptionId)
            guard current.periodId == verified.period.id,
                current.kind == verified.period.kind
            else { throw SubscriptionClientError(message: "Allowance period mismatch.") }
            usage = current
        } catch {
            usageIssue = String(localized: "Couldn’t load your current AI allowance.")
        }
    }
}
