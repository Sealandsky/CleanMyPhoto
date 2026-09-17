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

    // 年度订阅折算月价（如：折合 ¥4.83/月 或 $1.08/mo）
    func monthlyEquivalentPriceText(from products: [Product]) -> String? {
        guard self == .yearly,
              let product = products.first(where: { $0.id == self.rawValue }) else { return nil }
        let monthlyPrice = product.price / 12
        let formatted = monthlyPrice.formatted(product.priceFormatStyle)
        return String(format: String(localized: "monthly_breakdown_format"), formatted)
    }

    // 精炼试用徽章文案（如：7 天免费，用于卡片内部精炼展示）。
    // eligibleForIntroOffer 为 App Store 对该 Apple ID 的试用资格校验结果，
    // 已消耗过试用的用户不再展示试用徽章（避免「显示试用实际立即扣费」）
    func trialBadgeText(from products: [Product], eligibleForIntroOffer: Bool = true) -> String? {
        guard eligibleForIntroOffer,
              let product = products.first(where: { $0.id == self.rawValue }),
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return trialDurationText(offer)
    }

    // 免费试用展示文本（含试用结束后的扣费金额，App Store 审核 3.1.2 要求）
    func introductoryOfferText(from products: [Product], eligibleForIntroOffer: Bool = true) -> String? {
        guard eligibleForIntroOffer,
              let product = products.first(where: { $0.id == self.rawValue }),
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let trialText = trialDurationText(offer)
        return String(format: String(localized: "trial_then_format"), trialText, product.displayPrice, durationText)
    }

    // 购买按钮下方的扣费披露：明确试用时长与试用结束后将自动收取的金额
    func purchaseDisclosureText(from products: [Product], eligibleForIntroOffer: Bool = true) -> String? {
        guard let product = products.first(where: { $0.id == self.rawValue }) else { return nil }
        if eligibleForIntroOffer,
           let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
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
    func hasFreeTrial(from products: [Product], eligibleForIntroOffer: Bool = true) -> Bool {
        guard eligibleForIntroOffer,
              let product = products.first(where: { $0.id == self.rawValue }),
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return false }
        return true
    }

    // 动作按钮文案（根据所选方案类型及是否有试用资格智能匹配）
    func actionButtonTitle(from products: [Product], eligibleForIntroOffer: Bool = true) -> String {
        if hasFreeTrial(from: products, eligibleForIntroOffer: eligibleForIntroOffer) {
            return String(localized: "Start Free Trial")
        }
        switch self {
        case .monthly, .yearly:
            return String(localized: "Subscribe Now")
        case .lifetime:
            return String(localized: "Unlock Lifetime Access")
        }
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

    // 折扣信息（已按要求移除省 64% 标签）
    var savingsText: String? {
        nil
    }

    // 附加说明（月度与年度订阅均显示可随时取消，终身显示一次性买断）
    var subtitleText: String? {
        switch self {
        case .monthly, .yearly: return String(localized: "Cancel anytime")
        case .lifetime: return String(localized: "One-time Purchase · Lifetime Access")
        }
    }

    // 终身会员划线参考原价（根据 StoreKit 真实价格与货币代码动态计算）
    func lifetimeOriginalPriceText(from products: [Product]) -> String {
        guard let product = products.first(where: { $0.id == self.rawValue }) else {
            return "¥168.00"
        }

        let currencyCode = product.priceFormatStyle.currencyCode

        // 人民币区域固定锚定到 ¥168.00（带两位小数）
        if currencyCode == "CNY" {
            return Decimal(168).formatted(product.priceFormatStyle)
        }

        // 美元区域固定锚定到常用的 $49.99
        if currencyCode == "USD" {
            return "$49.99"
        }

        // 其他地区（如欧元、英镑、日元、加元等）：基于当前价格按约 1.9 倍（约 5.2 折）动态计算，并用本地货币格式化
        let originalPriceDecimal: Decimal
        if currencyCode == "JPY" || currencyCode == "KRW" {
            let rough = NSDecimalNumber(decimal: product.price * 1.9).doubleValue
            let rounded = (rough / 100.0).rounded() * 100.0
            originalPriceDecimal = Decimal(rounded)
        } else {
            let rough = NSDecimalNumber(decimal: product.price * 1.9).doubleValue
            let rounded = floor(rough) + 0.99
            originalPriceDecimal = Decimal(rounded)
        }

        return originalPriceDecimal.formatted(product.priceFormatStyle)
    }
}
