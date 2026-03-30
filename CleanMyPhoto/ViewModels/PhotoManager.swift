//
//  PhotoManager.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/7.
//

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
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMorePhotos: Bool = true
    @Published var hasLoadedOnce: Bool = false
    @Published var errorMessage: String?

    private let imageManager = PHCachingImageManager()
    private let maxPhotoCount = 50
    private var currentFetchOffset = 0

    var trashCount: Int {
        pendingDeletionIDs.count
    }

    init() {
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
            errorMessage = "Photo library access is required to use this app."
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
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        fetchOptions.includeAllBurstAssets = false

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
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

        // 预加载前3张和后3张图片
        preloadAssets()

        if allPhotos.isEmpty {
            errorMessage = "No photos found. Make sure you have photos in your photo library."
        }
    }

    // MARK: - Preload Assets
    func preloadAssets(photoIndex: Int? = nil, count: Int = 3) {
        // 确保数组不为空
        guard !displayedPhotos.isEmpty else {
            print("⚠️ No photos to preload")
            return
        }

        let index = photoIndex ?? 0
        let startIndex = max(0, index - count)
        let endIndex = min(displayedPhotos.count - 1, index + count)

        // 确保 startIndex <= endIndex
        guard startIndex <= endIndex else {
            print("⚠️ Invalid range: startIndex (\(startIndex)) > endIndex (\(endIndex))")
            return
        }

        print("🔄 Preloading photos from \(startIndex) to \(endIndex)")

        var assetsToPreload: [PHAsset] = []
        for i in startIndex...endIndex {
            assetsToPreload.append(displayedPhotos[i].asset)
        }

        // 使用 PHCachingImageManager 预加载图片
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        for asset in assetsToPreload {
            imageManager.startCachingImages(for: [asset], targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .aspectFit, options: options)
        }

        print("✅ Started caching \(assetsToPreload.count) images")
    }

    // MARK: - Stop Caching
    func stopCachingAssets(excluding: [PHAsset]) {
        imageManager.stopCachingImagesForAllAssets()
        // 只保留需要的图片在缓存中
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        imageManager.startCachingImages(for: excluding, targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .aspectFit, options: options)
    }

    // MARK: - Update Displayed Photos
    private func updateDisplayedPhotos() {
        displayedPhotos = allPhotos.filter { !pendingDeletionIDs.contains($0.id) }
    }

    // MARK: - Trash Management
    func addToTrash(_ photo: PhotoAsset) {
        pendingDeletionIDs.insert(photo.id)
        // 添加到 trashedAssets（如果还不存在）
        if !trashedAssets.contains(where: { $0.id == photo.id }) {
            trashedAssets.append(photo)
        }
        updateDisplayedPhotos()
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

            // Remove from all photos and clear pending deletions
            allPhotos.removeAll { trashedAssets.contains($0) }
            pendingDeletionIDs.removeAll()
            trashedAssets.removeAll()  // 清空 trashedAssets
            updateDisplayedPhotos()
        } catch {
            errorMessage = "Failed to delete photos: \(error.localizedDescription)"
        }
    }

    // MARK: - Image Loading Helper
    func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFit, result: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, _ in
            result(image)
        }
    }
}
