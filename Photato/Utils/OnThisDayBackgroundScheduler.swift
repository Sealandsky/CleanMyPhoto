import Foundation
import BackgroundTasks
import Photos

// MARK: - On This Day Background Scheduler
/// 负责注册与调度 iOS 系统后台静默任务（BGAppRefreshTask），
/// 保证夜间闲置充电时系统能够静默唤醒 App 自动补齐「往年今日」未来快照。
final class OnThisDayBackgroundScheduler {
    static let shared = OnThisDayBackgroundScheduler()
    static let taskIdentifier = "cn.bryan.photato.widget-refresh"

    private var isRegistered = false

    private init() {}

    /// 必须在 App 启动完成前（如 init()）同步注册后台任务标识
    func register() {
        guard !isRegistered else { return }
        isRegistered = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let appRefreshTask = task as? BGAppRefreshTask else { return }
            self?.handleBackgroundRefresh(task: appRefreshTask)
        }
    }

    /// 向系统预约下一次后台唤醒刷新（推荐在每次切到后台时调度）
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)

        let calendar = Calendar.current
        let now = Date()
        // 建议在次日凌晨 02:30 或至少 4 小时后，系统更倾向于在此充电锁屏窗口唤醒
        var targetDate = calendar.date(bySettingHour: 2, minute: 30, second: 0, of: now) ?? now.addingTimeInterval(4 * 3600)
        if targetDate <= now {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? now.addingTimeInterval(4 * 3600)
        }
        request.earliestBeginDate = max(targetDate, now.addingTimeInterval(4 * 3600))

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // 在未配置或特定受限环境下静默忽略
        }
    }

    /// 后台任务执行回调
    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // 1. 每次被唤醒，立即预约下一次，保持自动补仓链条不断裂
        scheduleNextRefresh()

        let refreshTask = Task { @MainActor in
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else {
                task.setTaskCompleted(success: true)
                return
            }

            let calendar = Calendar.current
            let now = Date()
            let currentYear = calendar.component(.year, from: now)
            let currentMonth = calendar.component(.month, from: now)
            let currentDay = calendar.component(.day, from: now)

            // 拉取今日照片分组
            let (rawGroups, isFallback) = await Task.detached(priority: .utility) {
                OnThisDayManager.computeRawYearGroups(
                    calendar: calendar,
                    currentYear: currentYear,
                    currentMonth: currentMonth,
                    currentDay: currentDay
                )
            }.value

            let groups = rawGroups.compactMap { item -> OnThisDayYearGroup? in
                guard !item.assets.isEmpty else { return nil }
                let photoAssets = item.assets.map { PhotoAsset(asset: $0) }
                return OnThisDayYearGroup(
                    id: isFallback ? "fallback-month-\(item.year)" : "year-\(item.year)",
                    year: item.year,
                    relativeYearsAgo: max(1, currentYear - item.year),
                    isMonthFallback: isFallback,
                    coverAsset: photoAssets[0],
                    photoCount: photoAssets.count,
                    photos: photoAssets,
                    locationName: nil
                )
            }

            // 重建今日快照 + 预计算未来多日
            await OnThisDayWidgetSnapshotWriter.shared.rebuild(
                using: groups,
                isMonthFallback: isFallback,
                permissionGranted: true,
                force: true
            )

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }
}
