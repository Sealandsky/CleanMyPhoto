import Foundation
import Photos

// MARK: - Timeline Month Item
/// 「时光归档」月份卡片数据模型：
/// 封装特定年月在图库中的照片资产、封面与数量信息。
struct TimelineMonthItem: Identifiable, Equatable, Hashable {
    /// 唯一标识，如 "2026-10"
    let id: String
    /// 归档年份，如 2026
    let year: Int
    /// 归档月份，1...12
    let month: Int
    /// 本地化月份文本（如 "10月"、"Oct"）
    let monthName: String
    /// 该月照片总数
    let photoCount: Int
    /// 代表封面照片（该月最新一张）
    let coverAsset: PHAsset?
    /// 该月起止时间
    let startDate: Date
    let endDate: Date

    var yearTitle: String {
        let currentLang = Locale.current.language.languageCode?.identifier ?? ""
        if currentLang.hasPrefix("zh") {
            return "\(year)年"
        }
        return "\(year)"
    }

    static func == (lhs: TimelineMonthItem, rhs: TimelineMonthItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.photoCount == rhs.photoCount &&
        lhs.coverAsset?.localIdentifier == rhs.coverAsset?.localIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Timeline Year Group
/// 单年份归档聚合模型
struct TimelineYearGroup: Identifiable, Equatable {
    let year: Int
    var months: [TimelineMonthItem]

    var id: Int { year }

    var totalCount: Int {
        months.reduce(0) { $0 + $1.photoCount }
    }
}
