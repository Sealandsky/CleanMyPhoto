import Photos
import Foundation

struct AlbumModel: Identifiable, Equatable {
    let id: String // PHAssetCollection.localIdentifier
    let collection: PHAssetCollection
    let title: String
    let assetCount: Int
    var coverAsset: PHAsset?
    /// 堆叠展示用缩略资产：最新的最多 3 张（旧→新排序，最新在末位）
    let stackAssets: [PHAsset]

    init(collection: PHAssetCollection) {
        self.id = collection.localIdentifier
        self.collection = collection
        self.title = collection.localizedTitle ?? String(localized: "Unnamed Album")

        // 获取相册内的资源数量
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType IN %@", [PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue])
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        self.assetCount = assets.count

        // 获取封面图（最后一张照片）
        if assets.count > 0 {
            self.coverAsset = assets.lastObject
        } else {
            self.coverAsset = nil
        }

        // 堆叠展示：取最新的最多 3 张（与封面同一次 fetch，无额外开销）
        var stack: [PHAsset] = []
        if assets.count > 0 {
            for i in max(0, assets.count - 3)..<assets.count {
                stack.append(assets.object(at: i))
            }
        }
        self.stackAssets = stack
    }

    static func == (lhs: AlbumModel, rhs: AlbumModel) -> Bool {
        lhs.id == rhs.id
    }

    init(id: String, title: String, assetCount: Int, coverAsset: PHAsset? = nil, stackAssets: [PHAsset] = []) {
        self.id = id
        self.collection = PHAssetCollection()
        self.title = title
        self.assetCount = assetCount
        self.coverAsset = coverAsset
        self.stackAssets = stackAssets
    }
}
