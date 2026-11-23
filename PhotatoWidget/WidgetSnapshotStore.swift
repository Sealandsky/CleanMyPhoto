import Foundation
import UIKit

// MARK: - Widget Snapshot Store
/// Widget 侧只读存储：从 App Group 同步读取快照与缩略图。
/// 必须保持轻量、同步、无网络、无 PhotoKit —— TimelineProvider 有超时预算。
enum WidgetSnapshotStore {
    /// 读取并校验快照：
    /// 1. 优先读取当天精确快照（今天或预计算的今天）；
    /// 2. 若跨天且未打开 App，读取 fallback.json（同月精选/历史回忆优雅降级）；
    /// 3. 若仍无，读取现有旧快照中依然可作为回忆兜底展示的数据（确保绝不轻易白板）。
    static func loadValidated() -> OnThisDayWidgetSnapshot? {
        let today = WidgetSharedContainer.todayKey()

        // 1. 优先命中今天专属快照（多日预计算中属于今天的快照）
        if let specificURL = WidgetSharedContainer.snapshotURL(for: today),
           let snapshot = loadSnapshot(from: specificURL),
           snapshot.isValid(for: today) {
            return snapshot
        }

        // 2. 命中主 snapshot.json（若是今天写入的）
        if let mainURL = WidgetSharedContainer.snapshotURL(),
           let snapshot = loadSnapshot(from: mainURL),
           snapshot.isValid(for: today) {
            return snapshot
        }

        // 3. 优雅降级兜底：查找独立 fallback.json
        if let fallbackURL = WidgetSharedContainer.fallbackSnapshotURL(),
           let snapshot = loadSnapshot(from: fallbackURL),
           snapshot.isValidAsFallback() {
            return ensureFallbackMode(snapshot)
        }

        // 4. 终极兜底：若有旧的主快照且有照片，将其平滑转为同月兜底模式展示
        if let mainURL = WidgetSharedContainer.snapshotURL(),
           let snapshot = loadSnapshot(from: mainURL),
           snapshot.isValidAsFallback() {
            return ensureFallbackMode(snapshot)
        }

        return nil
    }

    private static func loadSnapshot(from url: URL) -> OnThisDayWidgetSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(OnThisDayWidgetSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    /// 标记为兜底模式（标题自动切换为同月/回忆语义，避免日期事实误差）
    private static func ensureFallbackMode(_ snapshot: OnThisDayWidgetSnapshot) -> OnThisDayWidgetSnapshot {
        if snapshot.isMonthFallback { return snapshot }
        return OnThisDayWidgetSnapshot(
            schemaVersion: snapshot.schemaVersion,
            dayKey: snapshot.dayKey,
            generatedAt: snapshot.generatedAt,
            state: snapshot.state,
            isMonthFallback: true,
            years: snapshot.years.map { year in
                OnThisDayWidgetSnapshot.YearEntry(
                    id: year.id,
                    year: year.year,
                    relativeYearsAgo: year.relativeYearsAgo,
                    isMonthFallback: true,
                    photoCount: year.photoCount,
                    locationName: year.locationName,
                    coverImageFile: year.coverImageFile,
                    collageImageFiles: year.collageImageFiles
                )
            }
        )
    }

    /// 读取封面图
    static func loadCover(_ entry: OnThisDayWidgetSnapshot.YearEntry) -> UIImage? {
        loadImage(named: entry.coverImageFile)
    }

    /// 读取拼贴图（最多 count 张）
    static func loadCollage(_ entry: OnThisDayWidgetSnapshot.YearEntry, limit: Int = 5) -> [UIImage] {
        entry.collageImageFiles.prefix(limit).compactMap { loadImage(named: $0) }
    }

    private static func loadImage(named fileName: String) -> UIImage? {
        guard let url = WidgetSharedContainer.imageURL(named: fileName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
