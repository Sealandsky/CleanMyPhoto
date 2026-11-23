import Foundation
import WidgetKit

// MARK: - On This Day Timeline Entry
struct OnThisDayEntry: TimelineEntry {
    let date: Date
    /// 当前展示的年份在 snapshot.years 中的下标；空态/引导态为 nil
    let yearIndex: Int?
    let snapshot: OnThisDayWidgetSnapshot?
}

// MARK: - On This Day Timeline Provider
struct OnThisDayTimelineProvider: TimelineProvider {
    /// 年份轮换间隔：30 分钟。真机由系统调度节流；主 App 写快照后会主动 reload。
    private static let rotationStep: TimeInterval = 30 * 60
    private static let maxEntries = 8

    func placeholder(in context: Context) -> OnThisDayEntry {
        OnThisDayEntry(date: Date(), yearIndex: 0, snapshot: Self.placeholderSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (OnThisDayEntry) -> Void) {
        // Gallery 预览：优先真实快照，否则用占位
        let entry: OnThisDayEntry
        if let snapshot = WidgetSnapshotStore.loadValidated(), !snapshot.years.isEmpty {
            entry = OnThisDayEntry(date: Date(), yearIndex: 0, snapshot: snapshot)
        } else {
            entry = OnThisDayEntry(date: Date(), yearIndex: 0, snapshot: Self.placeholderSnapshot())
        }
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OnThisDayEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.loadValidated()

        // 快照无效（跨天 / 版本不符 / 不存在）→ 单个引导 entry，15 分钟后再试
        guard let snapshot else {
            let entry = OnThisDayEntry(date: now, yearIndex: nil, snapshot: nil)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }

        // 空数据 / 无权限 → 单个引导 entry，15 分钟后再试
        guard snapshot.state == .ready, !snapshot.years.isEmpty else {
            let entry = OnThisDayEntry(date: now, yearIndex: nil, snapshot: snapshot)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }

        // 一个年份一个 entry，按时间错开，实现轮换
        let yearCount = min(snapshot.years.count, Self.maxEntries)
        let entries = (0..<yearCount).map { index in
            OnThisDayEntry(
                date: now.addingTimeInterval(Double(index) * Self.rotationStep),
                yearIndex: index,
                snapshot: snapshot
            )
        }
        // 关键调度策略：循环走完或次日零点跨天时刷新，确保零点准时切入次日预存快照
        let calendar = Calendar.current
        let nextMidnight = calendar.startOfDay(for: now).addingTimeInterval(86400)
        let cycleEnd = now.addingTimeInterval(max(1, Double(yearCount)) * Self.rotationStep)
        let reloadDate = min(nextMidnight, cycleEnd)

        completion(Timeline(entries: entries, policy: .after(reloadDate)))
    }

    // MARK: - Placeholder
    private static func placeholderSnapshot() -> OnThisDayWidgetSnapshot {
        OnThisDayWidgetSnapshot(
            schemaVersion: OnThisDayWidgetSnapshot.currentSchemaVersion,
            dayKey: WidgetSharedContainer.todayKey(),
            generatedAt: Date(),
            state: .ready,
            isMonthFallback: false,
            years: [
                OnThisDayWidgetSnapshot.YearEntry(
                    id: "year-2023",
                    year: 2023,
                    relativeYearsAgo: 3,
                    isMonthFallback: false,
                    photoCount: 12,
                    locationName: nil,
                    coverImageFile: "",
                    collageImageFiles: []
                )
            ]
        )
    }
}
