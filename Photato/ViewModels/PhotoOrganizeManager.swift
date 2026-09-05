import Foundation
import Photos

@MainActor
@Observable
final class PhotoOrganizeManager {
    var isAnalyzing: Bool = false
    var analysisProgress: Double = 0
    var currentStep: String = ""
    var scanResults: [OrganizeCategory: [OrganizeScanGroup]] = [:]
    var categoryStats: [OrganizeCategory: Int] = [:]
    var totalPhotoCount: Int = 0
    var categoryPageStates: [OrganizeCategory: OrganizeCategoryPageState] = [:]
    var hasLoadedInitialData = false

    let similarityManager = PhotoSimilarityManager()
    let qualityAnalyzer = PhotoQualityAnalyzer()

    private var analysisTask: Task<Void, Never>?

    var totalGroupCount: Int {
        scanResults.values.reduce(0) { $0 + $1.count }
    }

    func stat(for category: OrganizeCategory) -> Int {
        categoryStats[category] ?? 0
    }

    // MARK: - Fetch System Photos (returns raw PHFetchResult, no wrapping)

    private func fetchSystemPHAssets() -> PHFetchResult<PHAsset> {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType IN %@", [
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        ])
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        fetchOptions.includeAllBurstAssets = false
        return PHAsset.fetchAssets(with: fetchOptions)
    }

    // MARK: - Quick Analysis

    func quickAnalysis() async {
        // 1. Try instant JSON cache load (no Core Data, no computation)
        if loadCacheSummary() {
            hasLoadedInitialData = true
            return
        }

        // 2. No JSON cache — fall back to Core Data path
        let hasCache = similarityManager.hasCachedData

        if hasCache {
            if let lg = similarityManager.largeFileGroup() {
                scanResults[.largeFiles] = [lg]
                categoryStats[.largeFiles] = lg.localIdentifiers.count
            }
            if let lq = similarityManager.lowQualityGroup() {
                scanResults[.lowQuality] = [lq]
                categoryStats[.lowQuality] = lq.localIdentifiers.count
            }
            let (similar, duplicates) = similarityManager.similarAndDuplicateGroups(skipValidation: true)
            if !similar.isEmpty {
                scanResults[.similar] = similar
                categoryStats[.similar] = similar.reduce(0) { $0 + $1.localIdentifiers.count }
            }
            if !duplicates.isEmpty {
                scanResults[.duplicates] = duplicates
                categoryStats[.duplicates] = duplicates.reduce(0) { $0 + $1.localIdentifiers.count }
            }
            if let bl = qualityAnalyzer.blurryGroup() {
                scanResults[.blurry] = [bl]
                categoryStats[.blurry] = bl.localIdentifiers.count
            }
            if let pf = qualityAnalyzer.poorFaceGroup() {
                scanResults[.poorFace] = [pf]
                categoryStats[.poorFace] = pf.localIdentifiers.count
            }
        }

        let fetchResult = fetchSystemPHAssets()
        totalPhotoCount = fetchResult.count
        scanMetadataCategories(from: fetchResult)

        // Save cache for next launch
        if totalGroupCount > 0 {
            saveCacheSummary(totalPhotoCount: totalPhotoCount)
        }
        hasLoadedInitialData = true
    }

    // MARK: - JSON Cache

    private var cacheFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(OrganizeCacheSummary.fileName)
    }

    @discardableResult
    private func loadCacheSummary() -> Bool {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let summary = try JSONDecoder().decode(OrganizeCacheSummary.self, from: data)

            guard summary.version == OrganizeCacheSummary.currentVersion else {
                try? FileManager.default.removeItem(at: cacheFileURL)
                return false
            }

            loadFlatCategoryFromCache(.screenshots, ids: summary.screenshotIds)
            loadFlatCategoryFromCache(.livePhotos, ids: summary.livePhotoIds)
            loadFlatCategoryFromCache(.videos, ids: summary.videoIds)
            loadFlatCategoryFromCache(.largeFiles, ids: summary.largeFileIds, potentialSpaceSaved: summary.largeFileTotalSize)
            loadFlatCategoryFromCache(.lowQuality, ids: summary.lowQualityIds)

            if !summary.similarGroups.isEmpty {
                scanResults[.similar] = summary.similarGroups.map { ids in
                    OrganizeScanGroup(
                        category: .similar,
                        title: String(localized: "\(ids.count) similar"),
                        localIdentifiers: ids
                    )
                }
                categoryStats[.similar] = summary.similarGroups.reduce(0) { $0 + $1.count }
            }

            if !summary.duplicateGroups.isEmpty {
                scanResults[.duplicates] = summary.duplicateGroups.map { ids in
                    OrganizeScanGroup(
                        category: .duplicates,
                        title: String(localized: "\(ids.count) duplicates"),
                        localIdentifiers: ids
                    )
                }
                categoryStats[.duplicates] = summary.duplicateGroups.reduce(0) { $0 + $1.count }
            }

            loadFlatCategoryFromCache(.blurry, ids: summary.blurryIds)
            loadFlatCategoryFromCache(.poorFace, ids: summary.poorFaceIds)

            totalPhotoCount = summary.totalPhotoCount
            return true
        } catch {
            try? FileManager.default.removeItem(at: cacheFileURL)
            return false
        }
    }

    private func saveCacheSummary(totalPhotoCount: Int) {
        let screenshotIds = identifiers(for: .screenshots)
        let livePhotoIds = identifiers(for: .livePhotos)
        let videoIds = identifiers(for: .videos)
        let largeFileIds = identifiers(for: .largeFiles)
        let largeFileTotalSize = scanResults[.largeFiles]?.first?.potentialSpaceSaved ?? 0
        let lowQualityIds = identifiers(for: .lowQuality)
        let blurryIds = identifiers(for: .blurry)
        let poorFaceIds = identifiers(for: .poorFace)
        let similarGroups = scanResults[.similar]?.map { $0.localIdentifiers } ?? []
        let duplicateGroups = scanResults[.duplicates]?.map { $0.localIdentifiers } ?? []

        let summary = OrganizeCacheSummary(
            version: OrganizeCacheSummary.currentVersion,
            timestamp: Date(),
            totalPhotoCount: totalPhotoCount,
            screenshotIds: screenshotIds,
            livePhotoIds: livePhotoIds,
            videoIds: videoIds,
            largeFileIds: largeFileIds,
            largeFileTotalSize: largeFileTotalSize,
            lowQualityIds: lowQualityIds,
            similarGroups: similarGroups,
            duplicateGroups: duplicateGroups,
            blurryIds: blurryIds,
            poorFaceIds: poorFaceIds
        )

        do {
            let data = try JSONEncoder().encode(summary)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            print("Failed to save organize cache: \(error)")
        }
    }

    // MARK: - Full Analysis

    func startFullAnalysis() {
        cancelAnalysis()

        analysisTask = Task {
            isAnalyzing = true
            analysisProgress = 0
            currentStep = ""
            scanResults.removeAll()
            categoryStats.removeAll()
            categoryPageStates.removeAll()

            let fetchResult = fetchSystemPHAssets()
            totalPhotoCount = fetchResult.count

            guard totalPhotoCount > 0 else {
                isAnalyzing = false
                return
            }

            let totalSteps: Double = 6

            currentStep = String(localized: "Scanning for metadata...")
            scanMetadataCategories(from: fetchResult)
            analysisProgress = 1.0 / totalSteps

            guard !Task.isCancelled else { return }

            currentStep = String(localized: "Scanning for large files...")
            await scanLargeFiles(from: fetchResult)
            analysisProgress = 2.0 / totalSteps

            guard !Task.isCancelled else { return }

            currentStep = String(localized: "Scanning for low quality...")
            await scanLowQuality(from: fetchResult)
            analysisProgress = 3.0 / totalSteps

            guard !Task.isCancelled else { return }

            currentStep = String(localized: "Scanning for similar photos...")
            await similarityManager.computeIfNeeded(assets: fetchResult)
            analysisProgress = 4.0 / totalSteps

            let (similar, duplicates) = similarityManager.similarAndDuplicateGroups()
            scanResults[.similar] = similar
            categoryStats[.similar] = similar.reduce(0) { $0 + $1.localIdentifiers.count }
            scanResults[.duplicates] = duplicates
            categoryStats[.duplicates] = duplicates.reduce(0) { $0 + $1.localIdentifiers.count }

            guard !Task.isCancelled else { return }

            currentStep = String(localized: "Analyzing photo quality...")
            await qualityAnalyzer.computeIfNeeded(assets: fetchResult)
            if let bl = qualityAnalyzer.blurryGroup() {
                scanResults[.blurry] = [bl]
                categoryStats[.blurry] = bl.localIdentifiers.count
            }
            if let pf = qualityAnalyzer.poorFaceGroup() {
                scanResults[.poorFace] = [pf]
                categoryStats[.poorFace] = pf.localIdentifiers.count
            }
            analysisProgress = 5.0 / totalSteps

            analysisProgress = 1.0
            currentStep = ""
            saveCacheSummary(totalPhotoCount: totalPhotoCount)
            isAnalyzing = false
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        analysisProgress = 0
        currentStep = ""
    }

    // MARK: - Scan: Metadata Categories (single pass)

    private func scanMetadataCategories(from fetchResult: PHFetchResult<PHAsset>) {
        var screenshotIds: [String] = []
        var livePhotoIds: [String] = []
        var videoIds: [String] = []

        fetchResult.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                screenshotIds.append(asset.localIdentifier)
            } else if asset.mediaType == .image && asset.mediaSubtypes.contains(.photoLive) {
                livePhotoIds.append(asset.localIdentifier)
            } else if asset.mediaType == .video {
                videoIds.append(asset.localIdentifier)
            }
        }

        storeFlatCategory(.screenshots, identifiers: screenshotIds)
        storeFlatCategory(.livePhotos, identifiers: livePhotoIds)
        storeFlatCategory(.videos, identifiers: videoIds)
    }

    // MARK: - Shared Helpers

    private func storeFlatCategory(_ category: OrganizeCategory, identifiers: [String], potentialSpaceSaved: Int64 = 0) {
        categoryStats[category] = identifiers.count
        if !identifiers.isEmpty {
            scanResults[category] = [OrganizeScanGroup(
                category: category,
                title: category.localizedText,
                localIdentifiers: identifiers,
                potentialSpaceSaved: potentialSpaceSaved
            )]
        }
    }

    private func loadFlatCategoryFromCache(_ category: OrganizeCategory, ids: [String], potentialSpaceSaved: Int64 = 0) {
        guard !ids.isEmpty else { return }
        scanResults[category] = [OrganizeScanGroup(
            category: category,
            title: category.localizedText,
            localIdentifiers: ids,
            potentialSpaceSaved: potentialSpaceSaved
        )]
        categoryStats[category] = ids.count
    }

    private func identifiers(for category: OrganizeCategory) -> [String] {
        scanResults[category]?.flatMap { $0.localIdentifiers } ?? []
    }

    // MARK: - Scan: Large Files (Option A: >= 10MB, or >= 24MP & >= 6MB)

    static let minLargeFileSize: Int64 = 10 * 1024 * 1024       // 10MB 绝对门槛
    static let highResThreshold: Int = 6000 * 4000              // 2400 万像素 (如 iPhone 24MP/48MP/全景)
    static let highResMinSize: Int64 = 6 * 1024 * 1024          // 6MB (高像素下的体积门槛)

    private func scanLargeFiles(from fetchResult: PHFetchResult<PHAsset>) async {
        // 收集所有静态图片资产
        var candidates: [(identifier: String, asset: PHAsset, resolution: Int)] = []
        fetchResult.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image else { return }
            candidates.append((asset.localIdentifier, asset, asset.pixelWidth * asset.pixelHeight))
        }

        var sized: [(identifier: String, size: Int64)] = []
        let total = candidates.count
        let startProgress: Double = 1.0 / 6.0
        let endProgress: Double = 2.0 / 6.0

        for (index, candidate) in candidates.enumerated() {
            guard !Task.isCancelled else { break }
            analysisProgress = startProgress + (endProgress - startProgress) * Double(index) / Double(max(total, 1))

            let size = await similarityManager.getOrFetchFileSize(for: candidate.asset)
            // 判定条件：真实大小 >= 10MB，或者超高分辨率(>=24MP)且大小 >= 6MB
            if size >= Self.minLargeFileSize || (candidate.resolution >= Self.highResThreshold && size >= Self.highResMinSize) {
                sized.append((candidate.identifier, size))
            }
        }

        let sorted = sized.sorted { $0.size > $1.size }
        let totalSize = sorted.reduce(Int64(0)) { $0 + $1.size }
        storeFlatCategory(.largeFiles, identifiers: sorted.map(\.identifier), potentialSpaceSaved: totalSize)
    }

    // MARK: - Scan: Low Quality (two-pass: metadata filter → size check)

    private func scanLowQuality(from fetchResult: PHFetchResult<PHAsset>) async {
        let minResolution = 1920 * 1080
        let maxFileSize: Int64 = 50 * 1024

        // Pass 1: low-res candidates
        var candidates: [(identifier: String, asset: PHAsset, resolution: Int)] = []
        fetchResult.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image else { return }
            let resolution = asset.pixelWidth * asset.pixelHeight
            if resolution < minResolution {
                candidates.append((asset.localIdentifier, asset, resolution))
            }
        }

        // Pass 2: filter by file size
        var lowQuality: [(identifier: String, resolution: Int)] = []
        let total = candidates.count
        let startProgress: Double = 2.0 / 6.0
        let endProgress: Double = 3.0 / 6.0

        for (index, candidate) in candidates.enumerated() {
            guard !Task.isCancelled else { break }
            analysisProgress = startProgress + (endProgress - startProgress) * Double(index) / Double(max(total, 1))
            let size = await similarityManager.getOrFetchFileSize(for: candidate.asset)
            if size <= maxFileSize {
                lowQuality.append((candidate.identifier, candidate.resolution))
            }
        }

        let sorted = lowQuality.sorted { $0.resolution < $1.resolution }
        storeFlatCategory(.lowQuality, identifiers: sorted.map(\.identifier))
    }

    // MARK: - Paginated Category Loading

    func isCategoryLoaded(_ category: OrganizeCategory) -> Bool {
        guard let state = categoryPageStates[category] else { return false }
        if state.isLoading { return true }
        if category == .similar || category == .duplicates {
            return !state.groups.isEmpty || !state.hasMore
        } else {
            return !state.loadedPhotos.isEmpty || !state.hasMore
        }
    }

    func loadCategory(_ category: OrganizeCategory) async {
        guard !isCategoryLoaded(category) else { return }

        var state = OrganizeCategoryPageState()
        let groups = scanResults[category] ?? []
        state.allIdentifiers = identifiers(for: category)

        if category == .similar || category == .duplicates {
            state.hasMore = !groups.isEmpty
            categoryPageStates[category] = state
            if state.hasMore {
                await loadMoreGroups(for: category)
            }
        } else {
            state.hasMore = !state.allIdentifiers.isEmpty
            categoryPageStates[category] = state
            if state.hasMore {
                await loadMorePhotos(for: category)
            }
        }
    }

    // MARK: - Grouped Loading (similar/duplicates 分批按需加载)

    func loadMoreGroups(for category: OrganizeCategory) async {
        guard var state = categoryPageStates[category],
              state.hasMore,
              !state.isLoading else { return }

        state.isLoading = true
        categoryPageStates[category] = state

        let scanGroups = scanResults[category] ?? []
        let startIndex = state.groups.count
        let endIndex = min(startIndex + OrganizeCategoryPageState.groupBatchSize, scanGroups.count)

        guard startIndex < scanGroups.count else {
            state.hasMore = false
            state.isLoading = false
            categoryPageStates[category] = state
            return
        }

        let groupsToLoad = Array(scanGroups[startIndex..<endIndex])
        let batchIdentifiers = groupsToLoad.flatMap { $0.localIdentifiers }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: batchIdentifiers, options: nil)
        var assetMap: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            assetMap[asset.localIdentifier] = asset
        }

        var newGroups: [OrganizeGroupDisplay] = []
        var newPhotos: [PhotoAsset] = []

        for scanGroup in groupsToLoad {
            var displayGroup = OrganizeGroupDisplay(
                id: scanGroup.id,
                title: scanGroup.title,
                localIdentifiers: scanGroup.localIdentifiers
            )

            for identifier in scanGroup.localIdentifiers {
                if let asset = assetMap[identifier] {
                    let photoAsset = PhotoAsset(asset: asset)
                    displayGroup.loadedPhotos.append(photoAsset)
                    newPhotos.append(photoAsset)
                }
            }

            if let best = displayGroup.loadedPhotos.max(by: {
                $0.asset.pixelWidth * $0.asset.pixelHeight < $1.asset.pixelWidth * $1.asset.pixelHeight
            }) {
                displayGroup.bestPhotoId = best.id
            }

            newGroups.append(displayGroup)
        }

        state.groups.append(contentsOf: newGroups)
        state.loadedPhotos.append(contentsOf: newPhotos)
        state.currentPage += 1
        state.hasMore = endIndex < scanGroups.count
        state.isLoading = false
        categoryPageStates[category] = state

        // 异步后台补齐这批分组的大小，不阻塞主线程上屏
        let groupIdsToFill = newGroups.map { $0.id }
        Task { [weak self] in
            await self?.fillGroupSizes(for: category, targetGroupIds: groupIdsToFill)
        }
    }

    /// 后台补齐各组合计大小：异步低优先级逐张读缓存尺寸，平滑更新
    private func fillGroupSizes(for category: OrganizeCategory, targetGroupIds: [String]) async {
        guard var state = categoryPageStates[category] else { return }
        let targetSet = Set(targetGroupIds)

        for i in 0..<state.groups.count {
            if targetSet.contains(state.groups[i].id) && state.groups[i].totalSize == 0 {
                var total: Int64 = 0
                for photo in state.groups[i].loadedPhotos {
                    total += await similarityManager.getOrFetchFileSize(for: photo.asset)
                }
                state.groups[i].totalSize = total
                categoryPageStates[category] = state
            }
        }
    }

    func groups(for category: OrganizeCategory) -> [OrganizeGroupDisplay] {
        categoryPageStates[category]?.groups ?? []
    }

    func hasMoreGroups(for category: OrganizeCategory) -> Bool {
        categoryPageStates[category]?.hasMore ?? false
    }

    func loadMore(for category: OrganizeCategory) async {
        if category == .similar || category == .duplicates {
            await loadMoreGroups(for: category)
        } else {
            await loadMorePhotos(for: category)
        }
    }

    // MARK: - Flat Loading (screenshots, large files, low quality)

    func loadMorePhotos(for category: OrganizeCategory) async {
        guard var state = categoryPageStates[category],
              state.hasMore,
              !state.isLoading else { return }

        state.isLoading = true
        categoryPageStates[category] = state

        let startIndex = state.currentPage * OrganizeCategoryPageState.pageSize
        let endIndex = min(startIndex + OrganizeCategoryPageState.pageSize, state.allIdentifiers.count)

        guard startIndex < state.allIdentifiers.count else {
            state.hasMore = false
            state.isLoading = false
            categoryPageStates[category] = state
            return
        }

        let identifiersToLoad = Array(state.allIdentifiers[startIndex..<endIndex])
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiersToLoad, options: nil)

        var assetMap: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            assetMap[asset.localIdentifier] = asset
        }

        var newPhotos: [PhotoAsset] = []
        for identifier in identifiersToLoad {
            if let asset = assetMap[identifier] {
                newPhotos.append(PhotoAsset(asset: asset))
            }
        }

        state.loadedPhotos.append(contentsOf: newPhotos)
        state.currentPage += 1
        state.hasMore = endIndex < state.allIdentifiers.count
        state.isLoading = false
        categoryPageStates[category] = state
    }

    func paginatedPhotos(for category: OrganizeCategory) -> [PhotoAsset] {
        categoryPageStates[category]?.loadedPhotos ?? []
    }

    func hasMorePhotos(for category: OrganizeCategory) -> Bool {
        categoryPageStates[category]?.hasMore ?? false
    }

    func isLoadingPhotos(for category: OrganizeCategory) -> Bool {
        categoryPageStates[category]?.isLoading ?? false
    }

    func clearCategoryState(_ category: OrganizeCategory) {
        categoryPageStates.removeValue(forKey: category)
    }

    /// 全屏收藏切换后同步状态，保证返回列表后心形角标与数据源一致
    func updateFavorite(photoID: String, isFavorite: Bool) {
        for category in categoryPageStates.keys {
            guard var state = categoryPageStates[category] else { continue }
            var changed = false
            for i in 0..<state.loadedPhotos.count {
                if state.loadedPhotos[i].id == photoID {
                    state.loadedPhotos[i].isFavorite = isFavorite
                    changed = true
                }
            }
            for i in 0..<state.groups.count {
                for j in 0..<state.groups[i].loadedPhotos.count {
                    if state.groups[i].loadedPhotos[j].id == photoID {
                        state.groups[i].loadedPhotos[j].isFavorite = isFavorite
                        changed = true
                    }
                }
            }
            if changed {
                categoryPageStates[category] = state
            }
        }
    }
}
