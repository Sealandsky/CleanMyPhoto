//
//  NavigationDestinations.swift
//  CleanMyPhoto
//

import Foundation

enum AlbumsDestination: Hashable {
    case albumPhotos(String) // AlbumModel.id
}

enum TimelineDestination: Hashable {
    case monthPhotos(String) // MonthAlbum.id
}
