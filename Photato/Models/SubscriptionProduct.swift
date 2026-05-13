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

    // 价格显示文本（优先使用 StoreKit 真实价格）
    func priceText(from products: [Product]) -> String {
        if let product = products.first(where: { $0.id == self.rawValue }) {
            return product.displayPrice
        }
        switch self {
        case .monthly: return "$2.99"
        case .yearly: return "$12.99"
        case .lifetime: return "$24.99"
        }
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
