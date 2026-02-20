//
//  SubscriptionProduct.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/21.
//

import Foundation

// MARK: - Subscription Type
enum SubscriptionType: String, CaseIterable {
    case monthly = "com.cleanmyphoto.subscription.monthly"
    case yearly = "com.cleanmyphoto.subscription.yearly"
    case lifetime = "com.cleanmyphoto.purchase.lifetime"

    // 显示名称
    var displayName: String {
        switch self {
        case .monthly: return "月度订阅"
        case .yearly: return "年度订阅"
        case .lifetime: return "终身会员"
        }
    }

    // 价格显示文本
    var priceText: String {
        switch self {
        case .monthly: return "¥12"
        case .yearly: return "¥68"
        case .lifetime: return "¥128"
        }
    }

    // 周期显示文本
    var durationText: String {
        switch self {
        case .monthly: return "/月"
        case .yearly: return "/年"
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
        case .yearly: return "省53%"
        case .lifetime: return nil
        }
    }

    // 附加说明
    var subtitleText: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return "最受欢迎"
        case .lifetime: return "一次性购买"
        }
    }
}
