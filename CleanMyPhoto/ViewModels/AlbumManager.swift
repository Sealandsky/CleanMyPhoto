//
//  AlbumManager.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI
import Photos
import Combine

@MainActor
class AlbumManager: ObservableObject {
    @Published var albums: [AlbumModel] = []
    @Published var currentAlbumPhotos: [PhotoAsset] = []
    @Published var isLoadingAlbums = false
    @Published var isLoadingPhotos = false

    let photoManager: PhotoManager

    init(photoManager: PhotoManager) {
        self.photoManager = photoManager
    }

    // 获取用户相簿（排除智能相簿）
    func fetchUserAlbums() async {
        isLoadingAlbums = true
        defer { isLoadingAlbums = false }

        let options = PHFetchOptions()
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        )

        var albums: [AlbumModel] = []
        userAlbums.enumerateObjects { collection, _, _ in
            let album = AlbumModel(collection: collection)
            // 只显示有照片的相簿
            if album.assetCount > 0 {
                albums.append(album)
            }
        }

        // 按标题排序
        self.albums = albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // 获取指定相簿的照片
    func fetchPhotos(in album: AlbumModel) async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)

        let assets = PHAsset.fetchAssets(in: album.collection, options: fetchOptions)

        var photos: [PhotoAsset] = []
        assets.enumerateObjects { asset, _, _ in
            photos.append(PhotoAsset(asset: asset))
        }

        self.currentAlbumPhotos = photos
    }

    // 获取过滤后的照片（排除已删除的）
    var displayedAlbumPhotos: [PhotoAsset] {
        currentAlbumPhotos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }
}
