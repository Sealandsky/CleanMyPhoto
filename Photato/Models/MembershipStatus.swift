import Foundation

// MARK: - Membership Tier
enum MembershipTier: String, Codable {
    case free = "free"
    case monthly = "monthly"
    case yearly = "yearly"
    case lifetime = "lifetime"
}

// MARK: - Membership Status
struct MembershipStatus {
    var currentTier: MembershipTier
    var trialStartDate: Date?

    // 计算试用期结束日期（7天后）
    var trialExpirationDate: Date? {
        guard let startDate = trialStartDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: 7, to: startDate)
    }

    // 试用期是否激活
    var isTrialActive: Bool {
        guard let expirationDate = trialExpirationDate else { return false }
        return Date() < expirationDate && currentTier == .free
    }

    // 剩余试用天数
    var remainingTrialDays: Int? {
        guard let expirationDate = trialExpirationDate else { return nil }
        guard let days = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day else {
            return nil
        }
        return max(0, days)
    }

    // 剩余试用时间（格式化字符串，含天和小时）
    var remainingTrialText: String? {
        guard let expirationDate = trialExpirationDate else { return nil }
        let components = Calendar.current.dateComponents([.day, .hour], from: Date(), to: expirationDate)
        let days = max(0, components.day ?? 0)
        let hours = max(0, components.hour ?? 0)

        if days > 0 {
            if hours > 0 {
                return String(localized: "\(days)d \(hours)h remaining")
            }
            return String(localized: "\(days)d remaining")
        }
        return String(localized: "\(hours)h remaining")
    }

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

        let trialTimestamp = defaults.double(forKey: "trialStartDate")
        let trialStart: Date? = trialTimestamp > 0 ? Date(timeIntervalSince1970: trialTimestamp) : nil

        return MembershipStatus(currentTier: tier, trialStartDate: trialStart)
    }

    // 保存到 UserDefaults
    func saveToStorage() {
        let defaults = UserDefaults.standard
        defaults.set(currentTier.rawValue, forKey: "currentMembershipTier")

        if let startDate = trialStartDate {
            defaults.set(startDate.timeIntervalSince1970, forKey: "trialStartDate")
        } else {
            defaults.removeObject(forKey: "trialStartDate")
        }
    }
}
