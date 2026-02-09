//
//  PhotoManager.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/7.
//

import SwiftUI
import Photos
import Combine

// MARK: - Photo Asset Model
struct PhotoAsset: Identifiable, Equatable {
    let id: String
    let asset: PHAsset

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
    }

    static func == (lhs: PhotoAsset, rhs: PhotoAsset) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Photo Section Model
struct PhotoSection: Identifiable {
    let id = UUID()
    let month: String
    let year: Int
    let photos: [PhotoAsset]

    var displayTitle: String {
        return month + " " + String(year)
    }
}

// MARK: - Photo Manager ViewModel
@MainActor
class PhotoManager: ObservableObject {
    @Published var allPhotos: [PhotoAsset] = []
    @Published var displayedPhotos: [PhotoAsset] = []
    @Published var displayedSections: [PhotoSection] = []
    @Published var pendingDeletionIDs: Set<String> = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMorePhotos: Bool = true
    @Published var errorMessage: String?

    private let imageManager = PHCachingImageManager()
    private let maxPhotoCount = 50
    private var currentFetchOffset = 0

    var trashCount: Int {
        pendingDeletionIDs.count
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
        defer { isLoading = false }

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
        let index = photoIndex ?? 0
        let startIndex = max(0, index - count)
        let endIndex = min(displayedPhotos.count - 1, index + count)

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
            imageManager.startCachingImages(for: [asset], targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options)
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

        imageManager.startCachingImages(for: excluding, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options)
    }

    // MARK: - Update Displayed Photos
    private func updateDisplayedPhotos() {
        displayedPhotos = allPhotos.filter { !pendingDeletionIDs.contains($0.id) }
        updateDisplayedSections()
    }

    // MARK: - Update Displayed Sections
    private func updateDisplayedSections() {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"

        var groupedPhotos: [String: (year: Int, month: String, photos: [PhotoAsset])] = [:]

        for photo in displayedPhotos {
            if let creationDate = photo.asset.creationDate {
                let month = formatter.string(from: creationDate)
                let year = calendar.component(.year, from: creationDate)
                let key = "\(year)-\(month)"

                if groupedPhotos[key] == nil {
                    groupedPhotos[key] = (year: year, month: month, photos: [])
                }
                groupedPhotos[key]?.photos.append(photo)
            }
        }

        // Convert to sections and sort by year and month (most recent first)
        let sections = groupedPhotos.map { (_, value) in
            PhotoSection(month: value.month, year: value.year, photos: value.photos)
        }

        // Sort sections by year and month (descending) using month numbers
        displayedSections = sections.sorted { section1, section2 in
            if section1.year != section2.year {
                return section1.year > section2.year
            }
            // Same year, compare months by converting month names to numbers
            let monthOrder = ["January": 1, "February": 2, "March": 3, "April": 4,
                              "May": 5, "June": 6, "July": 7, "August": 8,
                              "September": 9, "October": 10, "November": 11, "December": 12]
            let month1 = monthOrder[section1.month] ?? 0
            let month2 = monthOrder[section2.month] ?? 0
            return month1 > month2
        }
    }

    // MARK: - Trash Management
    func addToTrash(_ photo: PhotoAsset) {
        pendingDeletionIDs.insert(photo.id)
        updateDisplayedPhotos()
    }

    func restoreFromTrash(_ photoID: String) {
        pendingDeletionIDs.remove(photoID)
        updateDisplayedPhotos()
    }

    func isInTrash(_ photoID: String) -> Bool {
        pendingDeletionIDs.contains(photoID)
    }

    // MARK: - Get Trashed Assets
    func getTrashedAssets() -> [PhotoAsset] {
        allPhotos.filter { pendingDeletionIDs.contains($0.id) }
    }

    // MARK: - Empty Trash
    func emptyTrash() async {
        guard !pendingDeletionIDs.isEmpty else { return }

        let trashedAssets = getTrashedAssets()
        let assetsToDelete = trashedAssets.map { $0.asset }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }

            // Remove from all photos and clear pending deletions
            allPhotos.removeAll { trashedAssets.contains($0) }
            pendingDeletionIDs.removeAll()
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
