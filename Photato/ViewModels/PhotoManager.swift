import SwiftUI
import Photos
import Combine
import UIKit

// MARK: - Photo Manager ViewModel
@MainActor
class PhotoManager: ObservableObject {
    @Published var allPhotos: [PhotoAsset] = []
    @Published var displayedPhotos: [PhotoAsset] = []
    @Published var pendingDeletionIDs: Set<String> = []
    @Published var trashedAssets: [PhotoAsset] = []  // 存储被删除的照片对象
    @Published var favoriteOverrides: [String: Bool] = [:]
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMorePhotos: Bool = true
    @Published var hasLoadedOnce: Bool = false
    @Published var errorMessage: String?
    @Published var isSelectMode: Bool = false

    private let maxPhotoCount = 50
    private var currentFetchOffset = 0
    private(set) var statisticsManager: StatisticsManager?
    private(set) var totalPhotoCount: Int = 0

    var trashCount: Int {
        trashedAssets.count
    }

    init(statisticsManager: StatisticsManager? = nil) {
        self.statisticsManager = statisticsManager
        // 初始化时检查当前的权限状态
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Authorization
    func requestAuthorization() async {
        // 先尝试只读权限（更稳定）
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status

        if status == .authorized || status == .limited {
            await fetchAllPhotos()
        } else {
            errorMessage = String(localized: "Photo library access is required to use this app.")
        }
    }

    // MARK: - Fetch Photos
    func fetchAllPhotos() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        // Reset state
        currentFetchOffset = 0
        hasMorePhotos = true

        await fetchPhotos(offset: 0)
    }

    // MARK: - Fetch More Photos
    func fetchMorePhotos() async {
        guard !isLoadingMore && !isLoading && hasMorePhotos else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        await fetchPhotos(offset: allPhotos.count)
    }

    private func fetchPhotos(offset: Int) async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType IN %@", [PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue])
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        fetchOptions.includeAllBurstAssets = false

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        totalPhotoCount = fetchResult.count
        print("📸 FetchResult total count: \(fetchResult.count)")

        // Calculate range to fetch
        let startIndex = offset
        let endIndex = min(offset + maxPhotoCount, fetchResult.count)

        guard startIndex < fetchResult.count else {
            hasMorePhotos = false
            print("✅ No more photos to load")
            return
        }

        var assets: [PhotoAsset] = []
        for i in startIndex..<endIndex {
            let asset = fetchResult.object(at: i)
            assets.append(PhotoAsset(asset: asset))
        }

        // Check if there are more photos
        hasMorePhotos = endIndex < fetchResult.count

        if offset == 0 {
            allPhotos = assets
        } else {
            allPhotos.append(contentsOf: assets)
        }

        currentFetchOffset = allPhotos.count
        updateDisplayedPhotos()

        print("✅ Loaded \(assets.count) photos from index \(startIndex) to \(endIndex) (total: \(allPhotos.count))")
        print("✅ Has more photos: \(hasMorePhotos)")

        // 延后预加载，让 UI 先渲染
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            preloadAssets()
        }

        if allPhotos.isEmpty {
            errorMessage = String(localized: "No photos found. Make sure you have photos in your photo library.")
        }
    }

    // MARK: - Preload Assets
    private var lastPreheatIndex: Int = -1

    /// 首批素材初始预热：使用统一标准像素尺寸预热前排 36~48 张照片（覆盖前 3~4 屏）
    func preloadInitialAssets(columnCount: Int = GridColumnHelper.defaultCount) {
        guard !displayedPhotos.isEmpty else { return }
        lastPreheatIndex = 0

        let countToPreload = min(displayedPhotos.count, max(36, columnCount * 12))
        let assetsToPreload = displayedPhotos.prefix(countToPreload).map(\.asset)
        let targetSize = GridColumnHelper.thumbnailPixelSize(columnCount: columnCount)

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PhotoAssetImageManager.shared.startCachingImages(
            for: assetsToPreload,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )
    }

    /// 列表滑动动态预热窗口：8 张步长节流、方向感知、前瞻预热 48~60 张（覆盖连续划过 2~3 屏），并自动回收远端旧缓存
    func preheatAssets(around index: Int, in photos: [PhotoAsset], columnCount: Int) {
        guard !photos.isEmpty, index >= 0, index < photos.count else { return }
        // 步进节流：滑动跨度必须 >= 8 张（约 2~3 行）才触发一次批量预热，避免每张照片打断主线程
        guard lastPreheatIndex < 0 || abs(index - lastPreheatIndex) >= 8 else { return }

        let isScrollingDown = index >= lastPreheatIndex
        lastPreheatIndex = index

        let targetSize = GridColumnHelper.thumbnailPixelSize(columnCount: columnCount)
        // 4 列紧凑模式前瞻 60 张，2/3 列模式前瞻 48 张，始终覆盖 2.5~4 屏的猛烈划动提前量
        let preheatBatchSize = max(48, columnCount * 15)

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        // 1. 预热前方切片
        let prewarmRange: Range<Int>
        if isScrollingDown {
            let start = min(photos.count, index + 1)
            let end = min(photos.count, start + preheatBatchSize)
            prewarmRange = start..<end
        } else {
            let end = max(0, index)
            let start = max(0, end - preheatBatchSize)
            prewarmRange = start..<end
        }

        if !prewarmRange.isEmpty {
            let assetsToPrewarm = prewarmRange.map { photos[$0].asset }
            PhotoAssetImageManager.shared.startCachingImages(
                for: assetsToPrewarm,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            )
        }

        // 2. 释放离开视口较远的旧切片，防止系统底层解码位图无限堆积
        let cleanupThreshold = preheatBatchSize + 16
        if isScrollingDown && index > cleanupThreshold {
            let stopRange = max(0, index - (cleanupThreshold + 40))..<(index - cleanupThreshold)
            if !stopRange.isEmpty {
                let assetsToStop = stopRange.map { photos[$0].asset }
                PhotoAssetImageManager.shared.stopCachingImages(
                    for: assetsToStop,
                    targetSize: targetSize,
                    contentMode: .aspectFill,
                    options: options
                )
            }
        }
    }

    /// 兼容旧版预热接口
    func preloadAssets(photoIndex: Int? = nil, count: Int = 3) {
        if let index = photoIndex {
            let startIndex = max(0, index - count)
            let endIndex = min(displayedPhotos.count - 1, index + count)
            guard startIndex <= endIndex else { return }

            var assetsToPreload: [PHAsset] = []
            for i in startIndex...endIndex {
                assetsToPreload.append(displayedPhotos[i].asset)
            }

            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PhotoAssetImageManager.shared.startCachingImages(
                for: assetsToPreload,
                targetSize: ScreenSizeHelper.screenPhysicalSize,
                contentMode: .aspectFit,
                options: options
            )
        } else {
            preloadInitialAssets()
        }
    }

    // MARK: - Stop Caching
    func stopCachingAssets(excluding: [PHAsset]) {
        PhotoAssetImageManager.shared.stopCachingImagesForAllAssets()
        // 只保留需要的图片在缓存中
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PhotoAssetImageManager.shared.startCachingImages(
            for: excluding,
            targetSize: ScreenSizeHelper.screenPhysicalSize,
            contentMode: .aspectFit,
            options: options
        )
    }

    // MARK: - Update Displayed Photos
    private func updateDisplayedPhotos() {
        displayedPhotos = allPhotos.filter { !pendingDeletionIDs.contains($0.id) }
        lastPreheatIndex = -1
        updateStatistics()
    }

    /// 更新统计数据
    private func updateStatistics() {
        let videoCount = displayedPhotos.filter { $0.asset.mediaType == .video }.count
        statisticsManager?.updateStats(photoCount: totalPhotoCount, videoCount: videoCount, trash: trashCount)
    }

    // MARK: - Trash Management
    func addToTrash(_ photo: PhotoAsset) {
        pendingDeletionIDs.insert(photo.id)
        if !trashedAssets.contains(where: { $0.id == photo.id }) {
            trashedAssets.append(photo)
            Task {
                let size = await getAssetSize(photo.asset)
                statisticsManager?.recordDeletion(assetSize: size)
            }
        }
        updateDisplayedPhotos()
    }

    // MARK: - Favorite Management
    func isFavorite(_ photo: PhotoAsset) -> Bool {
        if let override = favoriteOverrides[photo.id] {
            return override
        }
        if let index = allPhotos.firstIndex(where: { $0.id == photo.id }) {
            return allPhotos[index].isFavorite
        }
        return photo.isFavorite
    }

    func toggleFavorite(_ photo: PhotoAsset) {
        let currentStatus = isFavorite(photo)
        let newValue = !currentStatus
        favoriteOverrides[photo.id] = newValue

        if let index = allPhotos.firstIndex(where: { $0.id == photo.id }) {
            allPhotos[index].isFavorite = newValue
            updateDisplayedPhotos()
        }

        Task {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest(for: photo.asset).isFavorite = newValue
                }
                // Refresh PHAsset in memory so computed properties pick up the new value
                let refreshed = PHAsset.fetchAssets(withLocalIdentifiers: [photo.asset.localIdentifier], options: nil)
                if let refreshedAsset = refreshed.firstObject {
                    if let idx = allPhotos.firstIndex(where: { $0.id == photo.id }) {
                        allPhotos[idx] = PhotoAsset(asset: refreshedAsset)
                        updateDisplayedPhotos()
                    }
                }
            } catch {
                print("Failed to toggle favorite for \(photo.id): \(error)")
                favoriteOverrides[photo.id] = currentStatus
                if let idx = allPhotos.firstIndex(where: { $0.id == photo.id }) {
                    allPhotos[idx].isFavorite = currentStatus
                    updateDisplayedPhotos()
                }
            }
        }
    }

    func restoreFromTrash(_ photoID: String) {
        pendingDeletionIDs.remove(photoID)
        // 从 trashedAssets 中移除
        trashedAssets.removeAll { $0.id == photoID }
        updateDisplayedPhotos()
    }

    func restoreAllFromTrash() {
        pendingDeletionIDs.removeAll()
        trashedAssets.removeAll()
        updateDisplayedPhotos()
    }

    func isInTrash(_ photoID: String) -> Bool {
        pendingDeletionIDs.contains(photoID)
    }

    // MARK: - Get Trashed Assets
    func getTrashedAssets() -> [PhotoAsset] {
        // 优先返回 trashedAssets，这样可以显示从相簿删除的照片
        return trashedAssets
    }

    // MARK: - Empty Trash
    func emptyTrash() async {
        guard !pendingDeletionIDs.isEmpty else { return }

        let assetsToDelete = trashedAssets.map { $0.asset }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }

            let count = trashedAssets.count
            var totalSize: Int64 = 0
            for asset in trashedAssets {
                totalSize += await getAssetSize(asset.asset)
            }
            statisticsManager?.recordDeletions(count: count, totalSize: totalSize)

            // Remove from all photos and clear pending deletions
            allPhotos.removeAll { trashedAssets.contains($0) }
            trashedAssets.removeAll()
            cleanupStaleDeletionIDs()
            updateDisplayedPhotos()
        } catch {
            errorMessage = String(localized: "Failed to delete photos: \(error.localizedDescription)")
        }
    }

    // MARK: - Statistics Helper

    private func cleanupStaleDeletionIDs() {
        let allIDs = Set(allPhotos.map(\.id))
        pendingDeletionIDs.subtract(allIDs)
    }

    private func getAssetSize(_ asset: PHAsset) async -> Int64 {
        await PHAssetSizeHelper.getAssetSize(asset)
    }

    // MARK: - Image Loading Helper
    func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFit, result: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        _ = PhotoAssetImageManager.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, _ in
            result(image)
        }
    }
}
