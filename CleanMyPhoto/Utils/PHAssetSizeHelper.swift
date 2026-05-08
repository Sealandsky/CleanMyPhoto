import Photos

enum PHAssetSizeHelper {
    static func getAssetSize(_ asset: PHAsset) async -> Int64 {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: Int64(data?.count ?? 0))
            }
        }
    }
}
