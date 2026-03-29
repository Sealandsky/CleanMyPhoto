//
//  AlbumCoverCache.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI
import Photos
import UIKit
import Combine

// MARK: - Album Cover Cache Manager
@MainActor
class AlbumCoverCache: ObservableObject {
    static let shared = AlbumCoverCache()

    @Published private var cache: [String: UIImage] = [:]  // albumID -> cached image
    private var cacheVersion: [String: String] = [:]  // albumID -> asset localIdentifier (用于检测封面变化)

    private init() {}

    // 获取缓存的封面
    func getCachedCover(for albumID: String) -> UIImage? {
        return cache[albumID]
    }

    // 检查封面是否需要更新
    func needsUpdate(for albumID: String, currentCoverAsset: PHAsset?) -> Bool {
        guard let asset = currentCoverAsset else {
            return false
        }

        let currentVersion = asset.localIdentifier
        let cachedVersion = cacheVersion[albumID]

        // 如果没有缓存版本，或者版本不同，需要更新
        return cachedVersion != currentVersion
    }

    // 更新缓存
    func updateCache(for albumID: String, image: UIImage, asset: PHAsset) {
        cache[albumID] = image
        cacheVersion[albumID] = asset.localIdentifier
        print("✅ Cached cover for album: \(albumID)")
    }

    // 清除特定相簿的缓存
    func clearCache(for albumID: String) {
        cache.removeValue(forKey: albumID)
        cacheVersion.removeValue(forKey: albumID)
    }

    // 清除所有缓存
    func clearAllCache() {
        cache.removeAll()
        cacheVersion.removeAll()
    }
}
