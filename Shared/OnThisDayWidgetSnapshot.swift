import Foundation

// MARK: - On This Day Widget Snapshot
/// 主 App → Widget 的只读数据契约。
/// 纯值类型、Codable、Sendable，禁止依赖 Photos / PhotoAsset / CoreLocation，
/// 以便同时被主 App 与 Widget Extension 两个进程编译。
struct OnThisDayWidgetSnapshot: Codable, Sendable {
    /// 快照结构版本；不一致时 widget 视为过期并引导用户打开 App。
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    /// 生成当天标识，规则与 OnThisDayManager 一致："yyyy-M-d"
    let dayKey: String
    let generatedAt: Date
    let state: State
    /// 整批数据是否为「历史同月精选」兜底（来自 manager.isMonthFallback）
    let isMonthFallback: Bool
    let years: [YearEntry]

    enum State: String, Codable, Sendable {
        case ready
        case empty
        case noPermission
    }

    struct YearEntry: Codable, Sendable, Identifiable {
        let id: String
        let year: Int
        let relativeYearsAgo: Int
        let isMonthFallback: Bool
        let photoCount: Int
        let locationName: String?
        /// 图片文件名（相对 App Group 的 onthisday/images/ 目录）
        let coverImageFile: String
        let collageImageFiles: [String]

        var deepLinkURL: URL {
            URL(string: "photato://onthisday?year=\(year)")!
        }
    }

    /// 快照是否可用于今天：结构版本一致且生成日就是今天
    func isValid(for dayKey: String) -> Bool {
        schemaVersion == Self.currentSchemaVersion && self.dayKey == dayKey
    }

    /// 作为兜底快照是否可用：结构版本一致，状态为 ready 且有照片数据
    func isValidAsFallback() -> Bool {
        schemaVersion == Self.currentSchemaVersion && state == .ready && !years.isEmpty
    }

    /// 与给定快照的内容指纹是否一致（用于去重，避免无谓重建）
    func fingerprintEquals(_ other: OnThisDayWidgetSnapshot) -> Bool {
        state == other.state &&
        isMonthFallback == other.isMonthFallback &&
        years.map { "\($0.id)/\($0.photoCount)/\($0.locationName ?? "")" } ==
            other.years.map { "\($0.id)/\($0.photoCount)/\($0.locationName ?? "")" }
    }
}
