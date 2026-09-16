import Foundation

// MARK: - Membership Tier
enum MembershipTier: String, Codable {
    case free = "free"
    case monthly = "monthly"
    case yearly = "yearly"
    case lifetime = "lifetime"
}

// MARK: - Membership Status
/// 会员档位完全由 StoreKit 权益（Transaction.currentEntitlements）推导并持久化；
/// 免费试用由 App Store 的 introductory offer 提供，本地不再维护试用倒计时。
struct MembershipStatus {
    var currentTier: MembershipTier

    // 是否为付费会员
    var isPremiumMember: Bool {
        currentTier != .free
    }
}

// MARK: - Persistence
extension MembershipStatus {
    // 从 UserDefaults 加载
    static func loadFromStorage() -> MembershipStatus {
        let defaults = UserDefaults.standard

        let tierRaw = defaults.string(forKey: "currentMembershipTier") ?? MembershipTier.free.rawValue
        let tier = MembershipTier(rawValue: tierRaw) ?? .free

        return MembershipStatus(currentTier: tier)
    }

    // 保存到 UserDefaults
    func saveToStorage() {
        let defaults = UserDefaults.standard
        defaults.set(currentTier.rawValue, forKey: "currentMembershipTier")
    }
}
