import Foundation

enum AlbumsDestination: Hashable {
    case albumDetail(String)     // AlbumModel.id: 二级相簿概览页
    case albumAllPhotos(String)  // AlbumModel.id: 三级全量照片网格
    case onThisDay(OnThisDayYearGroup) // 「往年今日」年份二级列表页
    case categoryResults(OrganizeCategory) // 媒体类型（视频、实况、截屏）全量浏览与管理
    case allPhotos // 全局「所有照片」现代图片流
    case monthArchive(TimelineMonthItem) // 「时光归档」单月图片流
    case allYearsArchive // 「时光归档」全部年份展开列表
    case personDetail(String) // PersonEntity.id: 二级人物专属照片流
    case allPeople // 「全部人物」总览列表
}
