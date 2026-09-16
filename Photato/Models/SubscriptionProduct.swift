import Foundation
import StoreKit

// MARK: - Subscription Type
enum SubscriptionType: String, CaseIterable {
    case monthly = "com.photato.subscription.monthly"
    case yearly = "com.photato.subscription.yearly"
    case lifetime = "com.photato.purchase.lifetime"

    // 显示名称
    var displayName: String {
        switch self {
        case .monthly: return String(localized: "Monthly")
        case .yearly: return String(localized: "Yearly")
        case .lifetime: return String(localized: "Lifetime")
        }
    }

    // 价格显示文本（优先使用 StoreKit 真实价格；加载失败时返回 nil，避免展示错误的货币）
    func priceText(from products: [Product]) -> String? {
        products.first(where: { $0.id == self.rawValue })?.displayPrice
    }

    // 免费试用展示文本（含试用结束后的扣费金额，App Store 审核 3.1.2 要求）
    func introductoryOfferText(from products: [Product]) -> String? {
        guard let product = products.first(where: { $0.id == self.rawValue }),
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let trialText = trialDurationText(offer)
        return String(format: String(localized: "trial_then_format"), trialText, product.displayPrice, durationText)
    }

    // 购买按钮下方的扣费披露：明确试用时长与试用结束后将自动收取的金额
    func purchaseDisclosureText(from products: [Product]) -> String? {
        guard let product = products.first(where: { $0.id == self.rawValue }) else { return nil }
        if let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            return String(
                format: String(localized: "purchase_disclosure_trial"),
                trialDurationText(offer), product.displayPrice, durationText
            )
        }
        if product.type == .autoRenewable {
            return String(format: String(localized: "purchase_disclosure_no_trial"), product.displayPrice, durationText)
        }
        return nil // 一次性买断，无后续扣费
    }

    // 是否可用免费试用开通（用于订阅按钮文案）
    func hasFreeTrial(from products: [Product]) -> Bool {
        introductoryOfferText(from: products) != nil
    }

    private func trialDurationText(_ offer: Product.SubscriptionOffer) -> String {
        if offer.period.unit == .day, offer.period.value == 7 {
            return String(localized: "7 Days Free")
        }
        return String(localized: "Free Trial")
    }

    // 周期显示文本
    var durationText: String {
        switch self {
        case .monthly: return String(localized: "/month")
        case .yearly: return String(localized: "/year")
        case .lifetime: return ""
        }
    }

    // 是否为推荐方案
    var isPopular: Bool {
        self == .yearly
    }

    // 折扣信息
    var savingsText: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return String(localized: "Save 64%")
        case .lifetime: return nil
        }
    }

    // 附加说明
    var subtitleText: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return String(localized: "Most Popular")
        case .lifetime: return String(localized: "One-time Purchase")
        }
    }
}
