import SwiftUI
import Photos
import Combine
import UIKit

// MARK: - Photo Manager ViewModel
@MainActor
class PhotoManager: NSObject, ObservableObject {
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
    @Published var showTrash: Bool = false

    private let maxPhotoCount = 50
    private var currentFetchOffset = 0
    /// 当前分页所基于的相册查询结果；作为 PHChange 增量比对的基准
    private var fetchResult: PHFetchResult<PHAsset>?
    private(set) var statisticsManager: StatisticsManager?
    /// 会员管理器引用：清空回收站成功后据实消耗免费删除额度（会员内部跳过）
    weak var membershipManager: MembershipManager?
    private(set) var totalPhotoCount: Int = 0

    var trashCount: Int {
        trashedAssets.count
    }

    init(statisticsManager: StatisticsManager? = nil) {
        super.init()
        self.statisticsManager = statisticsManager
        // 初始化时从 statisticsManager 继承历史缓存（如有），主线程 0 延迟
        if let cachedCount = statisticsManager?.currentPhotoCount, cachedCount > 0 {
            self.totalPhotoCount = cachedCount
        }
        // 初始化时检查当前的权限状态
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        // 监听系统相册变更（外部增删改、iCloud 下载完成等），保持数据与相册一致
        PHPhotoLibrary.shared().register(self)

        // 若已有权限，异步校验刷新系统照片总数，绝不阻塞主线程启动
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            Task(priority: .utility) { [weak self] in
                self?.updateTotalPhotoCountFromSystem()
            }
        }
    }

    // MARK: - Authorization
    func requestAuthorization() async {
        // 先尝试只读权限（更稳定）
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status

        if status == .authorized || status == .limited {
            updateTotalPhotoCountFromSystem()
            await fetchAllPhotos()
        } else {
            errorMessage = String(localized: "Photo library access is required to use this app.")
        }
    }

    /// 查询系统相册资源总数并同步至统计（与清理页卡片口径一致）
    func updateTotalPhotoCountFromSystem() {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let count = PHAsset.fetchAssets(with: options).count
        self.totalPhotoCount = count
        self.statisticsManager?.updateStats(photoCount: count, videoCount: 0, trash: trashCount)
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

    /// 图库查询条件（分页拉取与相册变更后的窗口重建共用同一套排序与过滤）
    private static func makeFetchOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType IN %@", [PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue])
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        fetchOptions.includeAllBurstAssets = false
        return fetchOptions
    }

    private func fetchPhotos(offset: Int) async {
        let fetchResult = PHAsset.fetchAssets(with: Self.makeFetchOptions())
        self.fetchResult = fetchResult
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

        // 首次加载完成，立即启动缩略图前瞻预热（覆盖前 3~4 屏），消除首屏及初次滑动灰块
        preloadInitialAssets()

        if allPhotos.isEmpty {
            errorMessage = String(localized: "No photos found. Make sure you have photos in your photo library.")
        }
    }

    // MARK: - Preload Assets
    private var lastPreheatIndex: Int = -1

    /// 统一执行批次预热：同时启动 PhotoKit 底层位图预热与 Swift 内存高速缓存（PhotoImageCache）装载，
    /// 确保列表滚动时单元格构造期（init）第 0 帧即可从内存同步命中 UIImage，彻底消灭灰块闪现
    private func preheatBatch(assets: [PHAsset], targetSize: CGSize, options: PHImageRequestOptions) {
        guard !assets.isEmpty else { return }
        PhotoAssetImageManager.shared.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )

        for asset in assets {
            if PhotoImageCache.shared.get(for: asset.localIdentifier, targetSize: targetSize, isHighQuality: false) == nil {
                _ = PhotoAssetImageManager.shared.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFill,
                    options: options
                ) { image, info in
                    guard let image = image else { return }
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    if isDegraded && max(image.size.width, image.size.height) < 100 { return }
                    PhotoImageCache.shared.set(
                        for: asset.localIdentifier,
                        targetSize: targetSize,
                        isHighQuality: false,
                        image: image
                    )
                }
            }
        }
    }

    /// 首批素材初始预热：使用统一标准像素尺寸预热前排 48~60 张照片（覆盖前 3~4 屏）
    func preloadInitialAssets(columnCount: Int = GridColumnHelper.defaultCount) {
        guard !displayedPhotos.isEmpty else { return }
        lastPreheatIndex = 0

        let countToPreload = min(displayedPhotos.count, max(48, columnCount * 15))
        let assetsToPreload = Array(displayedPhotos.prefix(countToPreload).map(\.asset))
        let targetSize = GridColumnHelper.thumbnailPixelSize(columnCount: columnCount)

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        preheatBatch(assets: assetsToPreload, targetSize: targetSize, options: options)
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
            preheatBatch(assets: assetsToPrewarm, targetSize: targetSize, options: options)
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
    /// 单张移入待处理照片
    func addToTrash(_ photo: PhotoAsset) {
        addToTrash([photo])
    }

    /// 批量移入待处理照片：仅标记隐藏并入站，不执行真实删除；统一只触发一次震动反馈。
    /// 删除统计只在 emptyTrash 真实删除成功时计入，避免双重计数。
    /// pendingDeletionIDs/trashedAssets 均为 @Published：合并为各一次赋值，
    /// 避免逐张 mutation 触发全局观察者 N 次重渲染。
    func addToTrash(_ photos: [PhotoAsset]) {
        guard !photos.isEmpty else { return }

        var newIDs = pendingDeletionIDs
        newIDs.formUnion(photos.map(\.id))
        pendingDeletionIDs = newIDs

        var newTrash = trashedAssets
        let existingIDs = Set(newTrash.map(\.id))
        newTrash.append(contentsOf: photos.filter { !existingIDs.contains($0.id) })
        trashedAssets = newTrash

        updateDisplayedPhotos()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
            // 免费删除额度按实际删除张数消耗（会员在 consume 内部跳过；失败路径不扣）
            membershipManager?.consumeFreeDeletions(count)

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

// MARK: - PHPhotoLibrary Change Observer
extension PhotoManager: PHPhotoLibraryChangeObserver {
    /// 回调来自任意后台队列：仅持有 PHChange（线程安全），切回主线程与 fetchResult 比对
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            guard let result = fetchResult,
                  let details = changeInstance.changeDetails(for: result) else { return }
            applyLibraryChanges(details)
        }
    }
}

private extension PhotoManager {
    /// 增量应用相册变更：
    /// - 已删除资产同步清出待处理集合（对 emptyTrash 自身触发的变更幂等）；
    /// - 结构性增删/移动按当前已加载深度重放首屏窗口，保持滚动位置语义；
    /// - 纯内容变更（收藏、iCloud 下载完成等）原地刷新对应 PhotoAsset。
    func applyLibraryChanges(_ details: PHFetchResultChangeDetails<PHAsset>) {
        fetchResult = details.fetchResultAfterChanges
        totalPhotoCount = details.fetchResultAfterChanges.count

        let removedIDs = Set(details.removedObjects.map(\.localIdentifier))
        if !removedIDs.isEmpty {
            pendingDeletionIDs.subtract(removedIDs)
            trashedAssets.removeAll { removedIDs.contains($0.id) }
        }

        let structural = !details.hasIncrementalChanges
            || details.hasMoves
            || !details.insertedObjects.isEmpty
            || !details.removedObjects.isEmpty

        if structural {
            reloadLoadedWindow()
        } else if !details.changedObjects.isEmpty {
            refreshChangedAssets(details.changedObjects)
        }

        updateDisplayedPhotos()
    }

    /// 按变更后的相册顺序重建已加载窗口（条数与此前一致，新照片进入窗口、窗口尾自然延后）
    private func reloadLoadedWindow() {
        let result = fetchResult ?? PHAsset.fetchAssets(with: Self.makeFetchOptions())
        fetchResult = result
        totalPhotoCount = result.count

        let loadedCount = allPhotos.count
        let endIndex = min(loadedCount, result.count)
        var assets: [PhotoAsset] = []
        assets.reserveCapacity(endIndex)
        for i in 0..<endIndex {
            assets.append(PhotoAsset(asset: result.object(at: i)))
        }
        allPhotos = assets
        hasMorePhotos = endIndex < result.count
    }

    /// changedObjects 携带的即是更新后的 PHAsset 实例，无需二次请求
    private func refreshChangedAssets(_ objects: [PHAsset]) {
        var freshByID: [String: PHAsset] = [:]
        freshByID.reserveCapacity(objects.count)
        for asset in objects {
            freshByID[asset.localIdentifier] = asset
        }

        for index in allPhotos.indices {
            if let fresh = freshByID[allPhotos[index].id] {
                allPhotos[index] = PhotoAsset(asset: fresh)
            }
        }
        for index in trashedAssets.indices {
            if let fresh = freshByID[trashedAssets[index].id] {
                trashedAssets[index] = PhotoAsset(asset: fresh)
            }
        }
    }
}
