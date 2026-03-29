//
//  AlbumModel.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import Photos
import Foundation

struct AlbumModel: Identifiable, Equatable {
    let id: String // PHAssetCollection.localIdentifier
    let collection: PHAssetCollection
    let title: String
    let assetCount: Int
    var coverAsset: PHAsset?

    init(collection: PHAssetCollection) {
        self.id = collection.localIdentifier
        self.collection = collection
        self.title = collection.localizedTitle ?? "Unnamed Album"

        // 获取相册内的资源数量
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        self.assetCount = assets.count

        // 获取封面图（最后一张照片）
        if assets.count > 0 {
            self.coverAsset = assets.lastObject
        } else {
            self.coverAsset = nil
        }
    }

    static func == (lhs: AlbumModel, rhs: AlbumModel) -> Bool {
        lhs.id == rhs.id
    }
}
