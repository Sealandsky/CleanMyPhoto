

import Foundation

enum AlbumsDestination: Hashable {
    case albumDetail(String)     // AlbumModel.id: 二级相簿概览页
    case albumAllPhotos(String)  // AlbumModel.id: 三级全量照片网格
}

enum TimelineDestination: Hashable {
    case monthPhotos(String) // MonthAlbum.id
}
