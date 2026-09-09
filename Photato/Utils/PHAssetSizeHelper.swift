import Photos

enum PHAssetSizeHelper {
    private static let cache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 10000
        return cache
    }()

    static func getCachedSize(for asset: PHAsset) -> Int64? {
        cache.object(forKey: asset.localIdentifier as NSString)?.int64Value
    }

    static func getAssetSize(_ asset: PHAsset) async -> Int64 {
        if let cached = getCachedSize(for: asset) {
            return cached
        }

        // 1. 优先使用 PHAssetResource 获取元数据文件大小（支持视频、图片、实况、iCloud，毫秒级响应）
        let fastSize = getFileSize(asset)
        if fastSize > 0 {
            cache.setObject(NSNumber(value: fastSize), forKey: asset.localIdentifier as NSString)
            return fastSize
        }

        // 2. 若为图片，回退到请求图片数据长度
        if asset.mediaType == .image {
            let size = await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = false
                options.deliveryMode = .fastFormat

                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                    continuation.resume(returning: Int64(data?.count ?? 0))
                }
            }
            if size > 0 {
                cache.setObject(NSNumber(value: size), forKey: asset.localIdentifier as NSString)
            }
            return size
        }

        return 0
    }

    static func getFileSize(_ asset: PHAsset) -> Int64 {
        if let cached = getCachedSize(for: asset) {
            return cached
        }
        let resources = PHAssetResource.assetResources(for: asset)
        let size = resources.reduce(Int64(0)) { sum, resource in
            sum + ((resource.value(forKey: "fileSize") as? Int64) ?? 0)
        }
        if size > 0 {
            cache.setObject(NSNumber(value: size), forKey: asset.localIdentifier as NSString)
        }
        return size
    }
}
