import Photos

enum PHAssetSizeHelper {
    static func getAssetSize(_ asset: PHAsset) async -> Int64 {
        // 1. 优先使用 PHAssetResource 获取元数据文件大小（支持视频、图片、实况、iCloud，毫秒级响应）
        let fastSize = getFileSize(asset)
        if fastSize > 0 {
            return fastSize
        }

        // 2. 若为图片，回退到请求图片数据长度
        if asset.mediaType == .image {
            return await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = false
                options.deliveryMode = .fastFormat

                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                    continuation.resume(returning: Int64(data?.count ?? 0))
                }
            }
        }

        return 0
    }

    static func getFileSize(_ asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.reduce(Int64(0)) { sum, resource in
            sum + ((resource.value(forKey: "fileSize") as? Int64) ?? 0)
        }
    }
}
