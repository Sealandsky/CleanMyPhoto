

import Foundation

enum AlbumsDestination: Hashable {
    case albumDetail(String)     // AlbumModel.id: 二级相簿概览页
    case albumAllPhotos(String)  // AlbumModel.id: 三级全量照片网格
    case onThisDay(OnThisDayYearGroup) // 「过去的今天」年份二级列表页
    case categoryResults(OrganizeCategory) // 媒体类型（视频、实况、截屏）全量浏览与管理
}
