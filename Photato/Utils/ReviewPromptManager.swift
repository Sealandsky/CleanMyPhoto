import Foundation
import StoreKit
import SwiftUI

/// 管理应用内原生评分引导（SKStoreReview / AppStore.requestReview）
/// 严格遵循苹果 HIG 规范，仅在用户完成清理等高价值操作后触达，同版本内最多提示一次
@MainActor
final class ReviewPromptManager {
    static let shared = ReviewPromptManager()
    private init() {}

    /// App Store 线上真实评论直达链接 (App ID: 6768487692)
    static let appStoreReviewURL = URL(string: "https://apps.apple.com/app/id6768487692?action=write-review")!

    private let minDeletionThreshold = 15
    private let lastPromptVersionKey = "ReviewPrompt_LastVersion"
    private let lastPromptDateKey = "ReviewPrompt_LastDate"
    private let minimumDaysBetweenPrompts = 20

    /// 评估是否满足评分引导条件并触发系统评分弹窗
    /// - Parameters:
    ///   - deletedCount: 本次删除的照片数量
    ///   - requestReview: 视图注入的 SwiftUI RequestReviewAction（可选）
    func requestReviewIfAppropriate(deletedCount: Int, requestReview: RequestReviewAction? = nil) {
        guard deletedCount >= minDeletionThreshold else { return }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let lastVersion = UserDefaults.standard.string(forKey: lastPromptVersionKey) ?? ""
        let lastDate = UserDefaults.standard.object(forKey: lastPromptDateKey) as? Date ?? .distantPast

        let daysSinceLast = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 999
        guard currentVersion != lastVersion && daysSinceLast >= minimumDaysBetweenPrompts else {
            return
        }

        // 记录状态避免频繁打扰
        UserDefaults.standard.set(currentVersion, forKey: lastPromptVersionKey)
        UserDefaults.standard.set(Date(), forKey: lastPromptDateKey)

        // 延迟 0.7 秒等待上层 Sheet 或 Alert 转场完全结束，确保交互流畅
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if let requestReview {
                requestReview()
            } else if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) {
                AppStore.requestReview(in: windowScene)
            }
        }
    }
}
