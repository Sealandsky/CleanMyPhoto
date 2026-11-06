import Foundation
import Photos

// MARK: - On This Day Year Group Model
/// 「过去的今天」年份卡片聚合数据模型：
/// 封装特定历史年份在今天（或同月兜底）拍摄的照片资产、封面、地名等摘要信息。
struct OnThisDayYearGroup: Identifiable, Equatable, Hashable {
    /// 唯一标识，如 "year-2023"
    let id: String
    /// 拍摄历史年份，如 2023
    let year: Int
    /// 相对当前年份的年数（如 3，表示 3 年前）
    let relativeYearsAgo: Int
    /// 是否为历史同月兜底（false 表示严格匹配当天月日，true 表示同月精选兜底）
    let isMonthFallback: Bool
    /// 当年今日拍下的第一张照片（忠实按时间排序的第一张）
    let coverAsset: PhotoAsset
    /// 当天拍下的照片总数
    let photoCount: Int
    /// 当天全部照片列表（按拍摄时间升序）
    let photos: [PhotoAsset]
    /// 基于反地理编码解析的代表性地名（如 "日本东京"、"杭州市"）
    var locationName: String?

    static func == (lhs: OnThisDayYearGroup, rhs: OnThisDayYearGroup) -> Bool {
        lhs.id == rhs.id &&
        lhs.photoCount == rhs.photoCount &&
        lhs.coverAsset.id == rhs.coverAsset.id &&
        lhs.locationName == rhs.locationName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
