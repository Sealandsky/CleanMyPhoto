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

    // 免费试用展示文本（仅在 StoreKit 配置了 introductory offer 时返回）
    func introductoryOfferText(from products: [Product]) -> String? {
        guard let subscription = products.first(where: { $0.id == self.rawValue })?.subscription,
              let offer = subscription.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
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
