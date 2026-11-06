import Foundation
import Photos
import SwiftUI
import Combine

// MARK: - On This Day Manager
/// 「过去的今天」数据管理层：
/// 1. 自动计算往年今天（严格 MM-dd）的所有历史照片；
/// 2. 当天无照片时，自动平滑兜底至「历史同月精选」；
/// 3. 取当年第一张照片作为封面（忠实呈现时间流逝）；
/// 4. 异步解析拍摄地名，按天会话级缓存，保证页面秒开与丝滑体验。
@MainActor
final class OnThisDayManager: ObservableObject {
    /// 聚合后的年份卡片列表（按年份倒序排列，最新年份在前）
    @Published private(set) var yearGroups: [OnThisDayYearGroup] = []
    /// 加载中标记
    @Published private(set) var isLoading = false
    /// 是否已完成过首次拉取
    @Published private(set) var hasLoadedOnce = false
    /// 是否启用了历史同月兜底模式
    @Published private(set) var isMonthFallback = false

    /// 记录最近一次加载的自然日标识（如 "2026-10-29"），防止单日内反复无谓重算
    private var lastFetchDayKey = ""

    /// 拉取或刷新「过去的今天」
    func fetchOnThisDay(forceRefresh: Bool = false) async {
        guard !isLoading else { return }

        let now = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentDay = calendar.component(.day, from: now)
        let dayKey = "\(currentYear)-\(currentMonth)-\(currentDay)"

        // 单日内非强制刷新时直接命中缓存
        if !forceRefresh && hasLoadedOnce && lastFetchDayKey == dayKey {
            return
        }

        // 权限校验
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            yearGroups = []
            hasLoadedOnce = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 后台异步计算，避免阻塞主线程动画
        let (rawGroups, isFallback) = await Task.detached(priority: .userInitiated) { () -> ([(year: Int, assets: [PHAsset])], Bool) in
            return Self.computeRawYearGroups(
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

        withAnimation(.easeInOut(duration: 0.25)) {
            yearGroups = groups
            isMonthFallback = isFallback
            hasLoadedOnce = true
            lastFetchDayKey = dayKey
        }

        // 异步解析地名（基于反地理编码缓存与防抖机制）
        resolveLocations()
    }

    // MARK: - Core Computation (Background Thread)

    nonisolated private static func computeRawYearGroups(
        calendar: Calendar,
        currentYear: Int,
        currentMonth: Int,
        currentDay: Int
    ) -> ([(year: Int, assets: [PHAsset])], Bool) {
        // 1. 尝试精准匹配历史相同月日（往昔 30 年）
        var exactPredicates: [NSPredicate] = []

        for offset in 1...30 {
            let pastYear = currentYear - offset
            var comps = DateComponents()
            comps.year = pastYear
            comps.month = currentMonth
            comps.day = currentDay
            comps.hour = 0
            comps.minute = 0
            comps.second = 0

            guard let startOfDay = calendar.date(from: comps),
                  let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
                continue
            }

            // 闰年 2 月 29 日安全校验
            if calendar.component(.month, from: startOfDay) == currentMonth &&
               calendar.component(.day, from: startOfDay) == currentDay {
                exactPredicates.append(
                    NSPredicate(
                        format: "creationDate >= %@ AND creationDate < %@",
                        startOfDay as NSDate,
                        endOfDay as NSDate
                    )
                )
            }
        }

        if !exactPredicates.isEmpty {
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            options.includeAllBurstAssets = false
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            options.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: exactPredicates)

            let fetchResult = PHAsset.fetchAssets(with: options)
            if fetchResult.count > 0 {
                var grouped: [Int: [PHAsset]] = [:]
                for i in 0..<fetchResult.count {
                    let asset = fetchResult.object(at: i)
                    guard let creationDate = asset.creationDate else { continue }
                    let year = calendar.component(.year, from: creationDate)
                    grouped[year, default: []].append(asset)
                }

                let sortedYears = grouped.keys.sorted(by: >)
                var result: [(year: Int, assets: [PHAsset])] = []
                for year in sortedYears {
                    guard let assets = grouped[year], !assets.isEmpty else { continue }
                    result.append((year: year, assets: assets))
                }

                if !result.isEmpty {
                    return (result, false)
                }
            }
        }

        // 2. 兜底策略：历史同月精选（若当天完全无照片）
        var monthPredicates: [NSPredicate] = []
        for offset in 1...20 {
            let pastYear = currentYear - offset
            var comps = DateComponents()
            comps.year = pastYear
            comps.month = currentMonth
            comps.day = 1
            comps.hour = 0
            comps.minute = 0
            comps.second = 0

            guard let startOfMonth = calendar.date(from: comps),
                  let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
                continue
            }
            monthPredicates.append(
                NSPredicate(
                    format: "creationDate >= %@ AND creationDate < %@",
                    startOfMonth as NSDate,
                    endOfMonth as NSDate
                )
            )
        }

        guard !monthPredicates.isEmpty else { return ([], false) }

        let monthOptions = PHFetchOptions()
        monthOptions.includeHiddenAssets = false
        monthOptions.includeAllBurstAssets = false
        monthOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        monthOptions.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: monthPredicates)

        let monthFetchResult = PHAsset.fetchAssets(with: monthOptions)
        guard monthFetchResult.count > 0 else { return ([], false) }

        var groupedMonth: [Int: [PHAsset]] = [:]
        for i in 0..<monthFetchResult.count {
            let asset = monthFetchResult.object(at: i)
            guard let creationDate = asset.creationDate else { continue }
            let year = calendar.component(.year, from: creationDate)
            if (groupedMonth[year]?.count ?? 0) < 50 {
                groupedMonth[year, default: []].append(asset)
            }
        }

        let sortedMonthYears = groupedMonth.keys.sorted(by: >)
        var fallbackResult: [(year: Int, assets: [PHAsset])] = []
        for year in sortedMonthYears {
            guard let assets = groupedMonth[year], !assets.isEmpty else { continue }
            fallbackResult.append((year: year, assets: assets))
        }

        return (fallbackResult, true)
    }

    // MARK: - Location Resolution

    /// 异步解析各年份代表性地名（优先查带有 GPS 定位的素材）
    private func resolveLocations() {
        for (index, group) in yearGroups.enumerated() {
            guard group.locationName == nil else { continue }
            // 优先从同批照片中选取带有 GPS 信息的素材
            let targetAsset = group.photos.first(where: { $0.asset.location != nil })?.asset ?? group.coverAsset.asset

            PhotoCaptionResolver.shared.resolveAddress(of: targetAsset) { [weak self] place in
                guard let self = self, let place = place, !place.isEmpty else { return }
                if index < self.yearGroups.count && self.yearGroups[index].id == group.id {
                    self.yearGroups[index].locationName = place
                }
            }
        }
    }
}
