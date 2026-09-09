import SwiftUI
import Photos
import Combine

// MARK: - Album Recommendation Cache Entry
struct AlbumRecommendationCacheEntry {
    let photos: [PhotoAsset]
    let timestamp: Date
    let albumPhotoCount: Int
    let albumHeadPhotoID: String?
}

@MainActor
class AlbumManager: ObservableObject {
    @Published var albums: [AlbumModel] = []
    @Published var currentAlbumPhotos: [PhotoAsset] = []
    @Published var isLoadingAlbums = false
    @Published var isLoadingPhotos = false

    let photoManager: PhotoManager

    // MARK: - Recommendation Cache
    /// 缓存每个相簿的推荐结果与快照签名（数量、首张照片ID、时间戳）
    private var recommendationCache: [String: AlbumRecommendationCacheEntry] = [:]

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
        fetchOptions.predicate = NSPredicate(format: "mediaType IN %@", [PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue])

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

    /// 全屏收藏切换后同步相簿照片状态
    func updateFavorite(photoID: String, isFavorite: Bool) {
        if let idx = currentAlbumPhotos.firstIndex(where: { $0.id == photoID }) {
            currentAlbumPhotos[idx].isFavorite = isFavorite
        }
    }

    /// 将照片添加到指定相簿并同步本地响应式数据
    @discardableResult
    func addAssetToAlbum(_ asset: PHAsset, in album: AlbumModel) async throws -> PhotoAsset {
        try await PHPhotoLibrary.shared().performChanges {
            let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [album.id],
                options: nil
            ).firstObject ?? album.collection
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            request.addAssets([asset] as NSArray)
        }

        // 添加成功后，实时同步到当前相簿照片列表最前面
        let newPhoto = PhotoAsset(asset: asset)
        if !currentAlbumPhotos.contains(where: { $0.id == newPhoto.id }) {
            withAnimation(.easeInOut(duration: 0.32)) {
                currentAlbumPhotos.insert(newPhoto, at: 0)
            }
        }

        // 重新获取该相簿最新元数据（数量、封面、堆叠等），刷新相簿列表展示
        let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil)
        if let updatedCollection = fetchResult.firstObject {
            let updatedAlbum = AlbumModel(collection: updatedCollection)
            if let idx = albums.firstIndex(where: { $0.id == album.id }) {
                albums[idx] = updatedAlbum
            }
        }
        invalidateRecommendationCache(for: album.id)
        return newPhoto
    }

    /// 批量将照片添加到指定相簿并同步本地响应式数据
    @discardableResult
    func addAssetsToAlbum(_ assets: [PHAsset], in album: AlbumModel) async throws -> [PhotoAsset] {
        guard !assets.isEmpty else { return [] }
        try await PHPhotoLibrary.shared().performChanges {
            let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [album.id],
                options: nil
            ).firstObject ?? album.collection
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            request.addAssets(assets as NSArray)
        }

        var newPhotos: [PhotoAsset] = []
        withAnimation(.easeInOut(duration: 0.32)) {
            for asset in assets.reversed() {
                let photo = PhotoAsset(asset: asset)
                if !currentAlbumPhotos.contains(where: { $0.id == photo.id }) {
                    currentAlbumPhotos.insert(photo, at: 0)
                    newPhotos.append(photo)
                }
            }
        }

        let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil)
        if let updatedCollection = fetchResult.firstObject {
            let updatedAlbum = AlbumModel(collection: updatedCollection)
            if let idx = albums.firstIndex(where: { $0.id == album.id }) {
                albums[idx] = updatedAlbum
            }
        }
        invalidateRecommendationCache(for: album.id)
        return newPhotos
    }

    // MARK: - Recommendation Cache Management
    /// 获取相簿推荐缓存（若当前相簿素材数量与首张素材 ID 均未变，则视为有效直接返回）
    func getCachedRecommendations(for albumID: String, currentPhotos: [PhotoAsset]) -> [PhotoAsset]? {
        guard let entry = recommendationCache[albumID] else { return nil }
        if entry.albumPhotoCount == currentPhotos.count &&
            entry.albumHeadPhotoID == currentPhotos.first?.id {
            return entry.photos
        }
        return nil
    }

    /// 检查缓存是否超过指定秒数（默认 15 分钟）需要静默刷新
    func isRecommendationCacheStale(for albumID: String, maxAge: TimeInterval = 900) -> Bool {
        guard let entry = recommendationCache[albumID] else { return true }
        return Date().timeIntervalSince(entry.timestamp) > maxAge
    }

    /// 写入或更新相簿推荐缓存
    func cacheRecommendations(_ photos: [PhotoAsset], for albumID: String, currentPhotos: [PhotoAsset]) {
        recommendationCache[albumID] = AlbumRecommendationCacheEntry(
            photos: photos,
            timestamp: Date(),
            albumPhotoCount: currentPhotos.count,
            albumHeadPhotoID: currentPhotos.first?.id
        )
    }

    /// 清除指定相簿的推荐缓存
    func invalidateRecommendationCache(for albumID: String) {
        recommendationCache.removeValue(forKey: albumID)
    }
}
