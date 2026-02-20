//
//  MembershipStatus.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/21.
//

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

    // 计算试用期结束日期（3天后）
    var trialExpirationDate: Date? {
        guard let startDate = trialStartDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: 3, to: startDate)
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
