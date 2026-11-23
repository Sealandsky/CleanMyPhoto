import Foundation

// MARK: - Widget Shared Container
/// App Group 共享容器的路径工具。两进程共用，全部返回可选值，绝不强制解包。
enum WidgetSharedContainer {
    static let groupID = "group.cn.bryan.photato.widget"
    static let widgetKind = "OnThisDayWidget"

    private static let folderName = "onthisday"
    private static let imagesFolderName = "images"
    private static let snapshotsFolderName = "snapshots"
    private static let snapshotFileName = "snapshot.json"
    private static let fallbackFileName = "fallback.json"

    /// App Group 容器根 URL
    static func rootURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    /// 数据目录 onthisday/
    static func dataDirectoryURL() -> URL? {
        rootURL()?.appendingPathComponent(folderName, isDirectory: true)
    }

    /// 多日快照子目录 onthisday/snapshots/
    static func snapshotsDirectoryURL() -> URL? {
        dataDirectoryURL()?.appendingPathComponent(snapshotsFolderName, isDirectory: true)
    }

    /// 今日/单日快照 JSON 路径（支持指定 dayKey，如 "2026-11-24"）
    static func snapshotURL(for dayKey: String? = nil) -> URL? {
        if let dayKey, !dayKey.isEmpty {
            return snapshotsDirectoryURL()?.appendingPathComponent("snapshot-\(dayKey).json")
        }
        return dataDirectoryURL()?.appendingPathComponent(snapshotFileName)
    }

    /// 优雅降级兜底快照路径 onthisday/fallback.json（用于长久未开 App 时的同月/往昔精选）
    static func fallbackSnapshotURL() -> URL? {
        dataDirectoryURL()?.appendingPathComponent(fallbackFileName)
    }

    /// 缩略图目录 onthisday/images/
    static func imagesDirectoryURL() -> URL? {
        dataDirectoryURL()?.appendingPathComponent(imagesFolderName, isDirectory: true)
    }

    /// 指定缩略图文件 URL
    static func imageURL(named fileName: String) -> URL? {
        imagesDirectoryURL()?.appendingPathComponent(fileName)
    }

    /// 确保目录存在（仅主 App 写入前调用；widget 只读，不创建）
    @discardableResult
    static func ensureDirectories() -> Bool {
        guard let dataDir = dataDirectoryURL(),
              let imagesDir = imagesDirectoryURL(),
              let snapshotsDir = snapshotsDirectoryURL() else { return false }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: nil)
            try fm.createDirectory(at: snapshotsDir, withIntermediateDirectories: true, attributes: nil)
            return fm.fileExists(atPath: dataDir.path)
        } catch {
            return false
        }
    }

    /// 今日 dayKey，规则与 OnThisDayManager 的 lastFetchDayKey 完全一致
    static func todayKey(now: Date = Date(), calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        return "\(year)-\(month)-\(day)"
    }
}
