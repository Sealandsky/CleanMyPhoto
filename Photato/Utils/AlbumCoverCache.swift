import SwiftUI
import Photos
import UIKit
import Combine

// MARK: - Album Cover Cache Manager
@MainActor
class AlbumCoverCache: ObservableObject {
    static let shared = AlbumCoverCache()

    private let cache = NSCache<NSString, UIImage>()
    private var cacheVersion: [String: String] = [:]  // albumID -> asset localIdentifier (用于检测封面变化)
    private var memoryWarningObserver: (any NSObjectProtocol)?

    private init() {
        // Sensible capacity constraints
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB

        // Automatically purge cache upon system memory warning
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clearAllCache()
            }
        }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public API

    /// 获取缓存的封面图片，可选校验版本
    func get(albumID: String, version: String? = nil) -> UIImage? {
        if let version = version {
            guard cacheVersion[albumID] == version else { return nil }
        }
        return cache.object(forKey: albumID as NSString)
    }

    /// 设置缓存的封面图片，根据像素尺寸计算内存开销并在 NSCache 中设置
    func set(albumID: String, version: String? = nil, image: UIImage) {
        let scale = image.scale > 0 ? image.scale : 1.0
        let cost = max(1, Int(image.size.width * scale * image.size.height * scale * 4))
        cache.setObject(image, forKey: albumID as NSString, cost: cost)
        if let version = version {
            cacheVersion[albumID] = version
        } else {
            cacheVersion.removeValue(forKey: albumID)
        }
    }

    /// 设置缓存的封面图片（便捷重载）
    func set(albumID: String, image: UIImage) {
        set(albumID: albumID, version: nil, image: image)
    }

    // 获取缓存的封面（兼容既有接口）
    func getCachedCover(for albumID: String) -> UIImage? {
        return get(albumID: albumID)
    }

    // 检查封面是否需要更新
    func needsUpdate(for albumID: String, currentCoverAsset: PHAsset?) -> Bool {
        guard let asset = currentCoverAsset else {
            return false
        }

        let currentVersion = asset.localIdentifier
        let cachedVersion = cacheVersion[albumID]

        // 如果没有缓存图像，或者没有缓存版本，或者版本不同，需要更新
        guard cache.object(forKey: albumID as NSString) != nil else {
            return true
        }

        return cachedVersion != currentVersion
    }

    // 更新缓存（兼容既有接口）
    func updateCache(for albumID: String, image: UIImage, asset: PHAsset) {
        set(albumID: albumID, version: asset.localIdentifier, image: image)
        print("✅ Cached cover for album: \(albumID)")
    }

    // 清除特定相簿的缓存
    func clearCache(for albumID: String) {
        cache.removeObject(forKey: albumID as NSString)
        cacheVersion.removeValue(forKey: albumID)
    }

    // 清除所有缓存
    @objc func clearAllCache() {
        cache.removeAllObjects()
        cacheVersion.removeAll()
    }
}
