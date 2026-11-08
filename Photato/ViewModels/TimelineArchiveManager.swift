import SwiftUI
import Photos
import Combine

// MARK: - Timeline Archive Manager
/// 「时光归档」模块数据管理器：
/// 1. 毫秒级按月构建轻量日期区间索引，前台仅预加载可视区域月份封面；
/// 2. 内存字典缓存 monthsByYear，切换年份胶囊时零等待原地平滑切换；
/// 3. 完全基于原生 Swift Concurrency 与 PhotoKit，无三方依赖。
@MainActor
final class TimelineArchiveManager: ObservableObject {
    @Published private(set) var availableYears: [Int] = []
    @Published var selectedYear: Int? = nil
    @Published private(set) var monthsByYear: [Int: [TimelineMonthItem]] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var hasLoadedOnce: Bool = false

    private var isFetching = false

    /// 获取当前选中年份的月份归档列表
    var currentMonths: [TimelineMonthItem] {
        guard let year = selectedYear else { return [] }
        return monthsByYear[year] ?? []
    }

    /// 初始或刷新加载时光归档
    func loadTimeline(forceRefresh: Bool = false) async {
        guard !isFetching else { return }
        if hasLoadedOnce && !forceRefresh && !availableYears.isEmpty { return }

        isFetching = true
        isLoading = true
        defer {
            isFetching = false
            isLoading = false
            hasLoadedOnce = true
        }

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        // 1. 异步极速拉取最早与最新照片日期，计算年份区间
        let (earliestDate, latestDate) = await Task.detached(priority: .userInitiated) { () -> (Date?, Date?) in
            let earliestOptions = PHFetchOptions()
            earliestOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            earliestOptions.fetchLimit = 1
            earliestOptions.predicate = NSPredicate(format: "isHidden == false")
            let earliest = PHAsset.fetchAssets(with: earliestOptions).firstObject?.creationDate

            let latestOptions = PHFetchOptions()
            latestOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            latestOptions.fetchLimit = 1
            latestOptions.predicate = NSPredicate(format: "isHidden == false")
            let latest = PHAsset.fetchAssets(with: latestOptions).firstObject?.creationDate

            return (earliest, latest)
        }.value

        var years: [Int] = []
        if let earliest = earliestDate, let latest = latestDate {
            let startYear = calendar.component(.year, from: earliest)
            let endYear = calendar.component(.year, from: latest)
            let minYear = min(startYear, endYear)
            let maxYear = max(startYear, endYear)
            years = Array(minYear...maxYear).reversed()
        } else {
            years = [currentYear]
        }

        self.availableYears = years
        let targetYear = selectedYear ?? years.first ?? currentYear
        self.selectedYear = targetYear

        // 2. 加载首选年份数据
        await loadMonths(for: targetYear)

        // 3. 后台低优先级预加载相邻年份，秒开切换
        if years.count > 1 {
            let nextYear = years.first(where: { $0 != targetYear })
            if let nextYear {
                Task(priority: .utility) { [weak self] in
                    await self?.loadMonths(for: nextYear)
                }
            }
        }
    }

    /// 切换选中年份
    func selectYear(_ year: Int) async {
        guard selectedYear != year else { return }
        selectedYear = year
        if monthsByYear[year] == nil {
            await loadMonths(for: year)
        }
    }

    /// 一次性预加载所有年份数据（供「全部年份」日历总览网格使用）
    func loadAllYears() async {
        for year in availableYears {
            if monthsByYear[year] == nil {
                await loadMonths(for: year)
            }
        }
    }

    /// 提取指定年份的 12 个月份归档（仅保留照片数 > 0 的月份）
    private func loadMonths(for year: Int) async {
        if monthsByYear[year] != nil { return }

        let calendar = Calendar.current
        let items = await Task.detached(priority: .userInitiated) { () -> [TimelineMonthItem] in
            var list: [TimelineMonthItem] = []

            for month in (1...12).reversed() {
                var startComponents = DateComponents()
                startComponents.year = year
                startComponents.month = month
                startComponents.day = 1

                guard let startDate = calendar.date(from: startComponents),
                      let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) else {
                    continue
                }

                let options = PHFetchOptions()
                options.predicate = NSPredicate(
                    format: "creationDate >= %@ AND creationDate < %@ AND isHidden == false",
                    startDate as NSDate,
                    endDate as NSDate
                )
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

                let result = PHAsset.fetchAssets(with: options)
                let count = result.count
                if count > 0 {
                    let cover = result.firstObject
                    let monthName = startDate.formatted(.dateTime.month())
                    let item = TimelineMonthItem(
                        id: "\(year)-\(month)",
                        year: year,
                        month: month,
                        monthName: monthName,
                        photoCount: count,
                        coverAsset: cover,
                        startDate: startDate,
                        endDate: endDate
                    )
                    list.append(item)
                }
            }
            return list
        }.value

        self.monthsByYear[year] = items
    }
}
