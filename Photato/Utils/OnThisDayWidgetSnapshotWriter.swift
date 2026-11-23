import Foundation
import UIKit
import Photos
import WidgetKit

// MARK: - On This Day Widget Snapshot Writer
/// 主 App 专用：把 OnThisDayManager 的 yearGroups（含 PHAsset）转换成可持久化的
/// OnThisDayWidgetSnapshot + 缩略图文件，原子写入 App Group 容器，并刷新 widget 时间线。
/// Widget 进程只读取这些文件，不接触 Photos。
final class OnThisDayWidgetSnapshotWriter {
    static let shared = OnThisDayWidgetSnapshotWriter()

    /// 缩略图生成上限
    private static let maxYears = 8
    private static let maxCollageImages = 5
    private static let coverPixelSize = CGSize(width: 360, height: 360)
    private static let collagePixelSize = CGSize(width: 320, height: 320)
    private static let jpegCompression: CGFloat = 0.75

    private var isWriting = false
    /// 防抖任务：地名回填等高频小改动会合并
    private var pendingWork: Task<Void, Never>?

    private init() {}

    /// 公开入口：请求重建快照。会做防抖与去重。
    /// - Parameters:
    ///   - groups: 当前年份分组
    ///   - isMonthFallback: 是否为同月兜底
    ///   - permissionGranted: 照片权限是否已授予
    ///   - force: 强制重写（下拉刷新 / 图库真删除后）
    func rebuild(
        using groups: [OnThisDayYearGroup],
        isMonthFallback: Bool,
        permissionGranted: Bool,
        force: Bool = false
    ) async {
        pendingWork?.cancel()
        let work = Task { @MainActor in
            // 防抖：合并短时间内多次触发（如地名逐个回填、批量删除）
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self.performRebuild(
                using: groups,
                isMonthFallback: isMonthFallback,
                permissionGranted: permissionGranted,
                force: force
            )
        }
        pendingWork = work
        await work.value
    }

    @MainActor
    private func performRebuild(
        using groups: [OnThisDayYearGroup],
        isMonthFallback: Bool,
        permissionGranted: Bool,
        force: Bool
    ) async {
        guard !isWriting else { return }
        guard let snapshotURL = WidgetSharedContainer.snapshotURL(),
              WidgetSharedContainer.ensureDirectories() else { return }

        // 1. 计算目标状态
        let state: OnThisDayWidgetSnapshot.State
        if !permissionGranted {
            state = .noPermission
        } else if groups.isEmpty {
            state = .empty
        } else {
            state = .ready
        }

        // 2. 构造 entry 元数据（图片稍后落盘，文件名先按 year 规则生成）
        let selected = Array(groups.prefix(Self.maxYears))
        let entries: [OnThisDayWidgetSnapshot.YearEntry] = selected.map { group in
            let coverName = "cover-\(group.year).jpg"
            let collageNames = (0..<min(Self.maxCollageImages, group.photos.count)).map {
                "collage-\(group.year)-\($0).jpg"
            }
            return OnThisDayWidgetSnapshot.YearEntry(
                id: group.id,
                year: group.year,
                relativeYearsAgo: group.relativeYearsAgo,
                isMonthFallback: group.isMonthFallback,
                photoCount: group.photoCount,
                locationName: group.locationName,
                coverImageFile: coverName,
                collageImageFiles: collageNames
            )
        }

        let newSnapshot = OnThisDayWidgetSnapshot(
            schemaVersion: OnThisDayWidgetSnapshot.currentSchemaVersion,
            dayKey: WidgetSharedContainer.todayKey(),
            generatedAt: Date(),
            state: state,
            isMonthFallback: isMonthFallback,
            years: entries
        )

        // 3. 去重：ready 状态且内容指纹一致时跳过（除非 force / 跨天）
        if !force,
           let existingData = try? Data(contentsOf: snapshotURL),
           let existing = try? JSONDecoder().decode(OnThisDayWidgetSnapshot.self, from: existingData),
           existing.isValid(for: newSnapshot.dayKey),
           existing.fingerprintEquals(newSnapshot) {
            return
        }

        isWriting = true
        defer { isWriting = false }

        // 4. 生成缩略图文件
        var writtenFiles = Set<String>()
        var validDayKeys: Set<String> = [newSnapshot.dayKey]

        for (index, group) in selected.enumerated() {
            guard !Task.isCancelled else { return }
            guard index < entries.count else { break }
            let entry = entries[index]

            // 封面
            if let cover = group.photos.first,
               let image = await Self.requestThumbnail(for: cover, pixelSize: Self.coverPixelSize),
               let data = image.jpegData(compressionQuality: Self.jpegCompression) {
                Self.writeAtomically(data, fileName: entry.coverImageFile)
                writtenFiles.insert(entry.coverImageFile)
            }

            // 拼贴图
            for (photoIndex, photo) in group.photos.prefix(Self.maxCollageImages).enumerated() {
                guard photoIndex < entry.collageImageFiles.count else { break }
                let name = entry.collageImageFiles[photoIndex]
                if let image = await Self.requestThumbnail(for: photo, pixelSize: Self.collagePixelSize),
                   let data = image.jpegData(compressionQuality: Self.jpegCompression) {
                    Self.writeAtomically(data, fileName: name)
                    writtenFiles.insert(name)
                }
            }
        }

        // 5. 原子写今日快照 JSON（写入主 snapshot.json 以及专有 snapshots/snapshot-{todayKey}.json）
        if let data = try? JSONEncoder().encode(newSnapshot) {
            try? data.write(to: snapshotURL, options: .atomic)
            if let specificTodayURL = WidgetSharedContainer.snapshotURL(for: newSnapshot.dayKey) {
                try? data.write(to: specificTodayURL, options: .atomic)
            }
        }

        // 6. 保存优雅降级兜底快照 fallback.json（永不过期、包含高质量精选照片）
        if state == .ready && !entries.isEmpty,
           let fallbackURL = WidgetSharedContainer.fallbackSnapshotURL() {
            let fallbackSnapshot = OnThisDayWidgetSnapshot(
                schemaVersion: OnThisDayWidgetSnapshot.currentSchemaVersion,
                dayKey: "fallback",
                generatedAt: Date(),
                state: .ready,
                isMonthFallback: true,
                years: entries
            )
            if let data = try? JSONEncoder().encode(fallbackSnapshot) {
                try? data.write(to: fallbackURL, options: .atomic)
            }
        }

        // 7. 多日预计算：在后台静默预计算未来 6 天（今天 + 6 天 = 完整一整周），实现用户一周不打开 App 也能天天自动换新图
        if state == .ready && permissionGranted {
            await precalculateFutureDays(
                daysAhead: 6,
                permissionGranted: permissionGranted,
                writtenFiles: &writtenFiles,
                validDayKeys: &validDayKeys
            )
        }

        // 8. 清理不再引用的旧缩略图与历史过期快照
        Self.pruneUnusedImages(keeping: writtenFiles)
        Self.pruneOldSnapshots(keepingDayKeys: validDayKeys)

        // 9. 通知 widget 刷新
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedContainer.widgetKind)
    }

    // MARK: - Multi-Day Pre-calculation (未来多日预计算)

    @MainActor
    private func precalculateFutureDays(
        daysAhead: Int = 6,
        permissionGranted: Bool,
        writtenFiles: inout Set<String>,
        validDayKeys: inout Set<String>
    ) async {
        guard permissionGranted else { return }
        let calendar = Calendar.current
        let now = Date()

        for offset in 1...daysAhead {
            guard !Task.isCancelled else { break }
            guard let targetDate = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let targetYear = calendar.component(.year, from: targetDate)
            let targetMonth = calendar.component(.month, from: targetDate)
            let targetDay = calendar.component(.day, from: targetDate)
            let targetDayKey = "\(targetYear)-\(targetMonth)-\(targetDay)"
            validDayKeys.insert(targetDayKey)

            // 检查对应单日快照是否已存在有效缓存
            if let existingURL = WidgetSharedContainer.snapshotURL(for: targetDayKey),
               let existingData = try? Data(contentsOf: existingURL),
               let existing = try? JSONDecoder().decode(OnThisDayWidgetSnapshot.self, from: existingData),
               existing.isValid(for: targetDayKey),
               existing.state == .ready {
                for year in existing.years {
                    writtenFiles.insert(year.coverImageFile)
                    for file in year.collageImageFiles {
                        writtenFiles.insert(file)
                    }
                }
                continue
            }

            // 在后台线程拉取目标日期的往年今日照片
            let (rawGroups, isFallback) = await Task.detached(priority: .utility) {
                OnThisDayManager.computeRawYearGroups(
                    calendar: calendar,
                    currentYear: targetYear,
                    currentMonth: targetMonth,
                    currentDay: targetDay
                )
            }.value

            guard !rawGroups.isEmpty else { continue }

            let selected = Array(rawGroups.prefix(Self.maxYears))
            let entries: [OnThisDayWidgetSnapshot.YearEntry] = selected.map { item in
                let coverName = "cover-\(targetDayKey)-\(item.year).jpg"
                let collageCount = min(Self.maxCollageImages, item.assets.count)
                let collageNames = (0..<collageCount).map {
                    "collage-\(targetDayKey)-\(item.year)-\($0).jpg"
                }
                return OnThisDayWidgetSnapshot.YearEntry(
                    id: isFallback ? "fallback-\(targetDayKey)-\(item.year)" : "year-\(targetDayKey)-\(item.year)",
                    year: item.year,
                    relativeYearsAgo: max(1, targetYear - item.year),
                    isMonthFallback: isFallback,
                    photoCount: item.assets.count,
                    locationName: nil,
                    coverImageFile: coverName,
                    collageImageFiles: collageNames
                )
            }

            let futureSnapshot = OnThisDayWidgetSnapshot(
                schemaVersion: OnThisDayWidgetSnapshot.currentSchemaVersion,
                dayKey: targetDayKey,
                generatedAt: Date(),
                state: .ready,
                isMonthFallback: isFallback,
                years: entries
            )

            // 写入图片文件
            for (index, item) in selected.enumerated() {
                guard !Task.isCancelled else { break }
                guard index < entries.count else { break }
                let entry = entries[index]

                if let coverAsset = item.assets.first,
                   let image = await Self.requestThumbnail(for: PhotoAsset(asset: coverAsset), pixelSize: Self.coverPixelSize),
                   let data = image.jpegData(compressionQuality: Self.jpegCompression) {
                    Self.writeAtomically(data, fileName: entry.coverImageFile)
                    writtenFiles.insert(entry.coverImageFile)
                }

                for (pIdx, asset) in item.assets.prefix(Self.maxCollageImages).enumerated() {
                    guard pIdx < entry.collageImageFiles.count else { break }
                    let name = entry.collageImageFiles[pIdx]
                    if let image = await Self.requestThumbnail(for: PhotoAsset(asset: asset), pixelSize: Self.collagePixelSize),
                       let data = image.jpegData(compressionQuality: Self.jpegCompression) {
                        Self.writeAtomically(data, fileName: name)
                        writtenFiles.insert(name)
                    }
                }
            }

            // 写入未来单日快照 JSON
            if let targetURL = WidgetSharedContainer.snapshotURL(for: targetDayKey),
               let data = try? JSONEncoder().encode(futureSnapshot) {
                try? data.write(to: targetURL, options: .atomic)
            }
        }
    }

    // MARK: - Helpers

    /// 用主 App 现成的图片管理器请求缩略图，转成 async。
    private static func requestThumbnail(for photo: PhotoAsset, pixelSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = false  // 快照生成不触发 iCloud 下载
            options.isSynchronous = false

            var resumed = false
            let lock = NSLock()
            func finish(_ image: UIImage?) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }

            _ = PhotoAssetImageManager.shared.requestImage(
                for: photo.asset,
                targetSize: pixelSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let image {
                    // 首张即接受（可能是 degraded 缩略图，widget 足够用），避免等待导致超时挂起
                    finish(image)
                } else {
                    // 无图：无论是否带 error 都 resume，杜绝 continuation 永久挂起
                    _ = info?[PHImageErrorKey]
                    finish(nil)
                }
            }
        }
    }

    private static func writeAtomically(_ data: Data, fileName: String) {
        guard let url = WidgetSharedContainer.imageURL(named: fileName) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func pruneUnusedImages(keeping: Set<String>) {
        guard let imagesDir = WidgetSharedContainer.imagesDirectoryURL() else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: imagesDir.path) else { return }
        for file in files where !keeping.contains(file) {
            try? fm.removeItem(at: imagesDir.appendingPathComponent(file))
        }
    }

    private static func pruneOldSnapshots(keepingDayKeys: Set<String>) {
        guard let snapshotsDir = WidgetSharedContainer.snapshotsDirectoryURL() else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: snapshotsDir.path) else { return }
        for file in files {
            if file.hasPrefix("snapshot-") && file.hasSuffix(".json") {
                let dayKey = file
                    .replacingOccurrences(of: "snapshot-", with: "")
                    .replacingOccurrences(of: ".json", with: "")
                if !keepingDayKeys.contains(dayKey) {
                    try? fm.removeItem(at: snapshotsDir.appendingPathComponent(file))
                }
            }
        }
    }
}
