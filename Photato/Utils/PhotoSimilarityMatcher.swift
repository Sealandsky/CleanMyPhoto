import Foundation
import Photos
import UIKit
import Vision
import CoreML
import CoreData

// MARK: - PhotoSimilarityMatcher
/// 以单张基准照片在全相册内检索视觉相似照片（详情页「更多类似照片」数据源）。
///
/// 特征提取使用 Vision 的 VNGenerateImageFeaturePrint：基准与候选统一走
/// 本地缩略图 → CGImage → 特征指纹流水线，特征距离越小越相似。
///
/// 核心规则：
/// - 强制排除基准照片自身（localIdentifier 枚举排除 + 结果二次校验）
/// - 特征一律取本地缩略图（小尺寸请求直接命中 Photos 缩略图缓存）：
///   iCloud 优化存储的真机上原片缺失时依然可匹配，网络访问始终关闭，
///   绝不触发云端下载；连本地缩略图都没有的素材（极少）才跳过
/// - 特征距离超过阈值（默认 0.6）的候选过滤，按距离升序取 Top N（默认 12）
///
/// 线程模型：全部计算在专用串行队列（userInitiated）执行，同一时刻仅一场
/// 检索在跑；进度与完成回调均派发到主线程。
///
/// 缓存：特征指纹持久化在 Core Data，并在首次使用时一次性载入会话级内存库——
/// 同一会话内跨照片查询纯内存（零 IO、零反序列化），进入任意详情页即时出结果。
/// 命中条件是素材未被编辑（modificationDate 一致）且特征管线版本一致
/// （OS 更新自动失效重算）。首扫全量计算并写通，重复检索零计算。
final class PhotoSimilarityMatcher {

    // MARK: - Shared

    static let shared = PhotoSimilarityMatcher()
    private init() {}

    // MARK: - Errors

    enum MatcherError: LocalizedError {
        /// 相册权限不足（denied / restricted / 未决策）
        case photoAccessDenied(PHAuthorizationStatus)
        /// 基准照片无法提取特征（本地无原图 / 元数据损坏 / Vision 失败）
        case baseFeatureUnavailable
        /// 主动取消，或被新一轮检索取代
        case cancelled

        var errorDescription: String? {
            switch self {
            case .photoAccessDenied(let status):
                return String(localized: "Photo library access unavailable (\(status.rawValue))")
            case .baseFeatureUnavailable:
                return String(localized: "Cannot extract features from the base photo")
            case .cancelled:
                return String(localized: "Matching cancelled")
            }
        }
    }

    // MARK: - Configuration

    /// 相似度阈值（特征距离）：0 = 完全一致；经验上 <0.3 近似重复，
    /// 0.3~0.8 同场景相似，>1 基本无关。0.6 兼顾查全率与噪声过滤。
    /// nonisolated：默认参数表达式在非隔离上下文求值
    nonisolated static let defaultMaxDistance: Float = 0.6
    /// 相簿推荐相似度阈值：相簿推荐需涵盖同场景、同事件或同题材素材，0.72 兼顾主题相关度与查全率
    nonisolated static let defaultAlbumMaxDistance: Float = 0.72
    /// 特征提取的缩略图边长：256px 直接命中本地缩略图缓存（iCloud 优化存储下
    /// 无需下载原图），基准与候选统一尺寸保证特征距离可比
    private static let inputPixelSize: CGFloat = 256
    /// 主尺寸取不到时的兜底边长（覆盖极端无中等缩略图的素材）
    private static let fallbackPixelSize: CGFloat = 160
    /// 进度回报节流步长：每处理 N 张向主线程回报一次（大相册防主线程刷屏）
    private static let progressStride = 10
    /// 会话级特征库容量上限：保持在 2,000 条（内存常驻仅 ~20MB）。
    /// 超出后由二级 LRU 机制淘汰，Core Data 磁盘持久层仍保留全量，支持毫秒级按需补查
    private static let maxSessionFeatureCount = 2_000

    // MARK: - Threading & Queues

    /// 后台静默特征索引构建专用低优先级串行队列（utility，温和慢跑、不与前台争抢算力）
    private let indexingQueue = DispatchQueue(label: "cn.bryan.photato.similarity-matcher.indexing", qos: .utility)
    /// 前台用户交互专用高优先级串行队列（userInitiated，秒级响应详情页与相簿匹配）
    private let queryQueue = DispatchQueue(label: "cn.bryan.photato.similarity-matcher.query", qos: .userInitiated)

    /// 当前有效任务令牌：仅在 queryQueue 上读写（线程 confinement 保证安全）
    private var activeToken: UUID?
    /// 相簿相似检索专用令牌：与单张照片检索互不冲突
    private var albumActiveToken: UUID?

    /// 前台活跃避让控制：当用户在详情页浏览翻页或相簿交互时，后台静默索引立即让步
    private var foregroundDebounceWorkItem: DispatchWorkItem?
    private let activityLock = NSLock()
    private(set) var isForegroundActive: Bool = false

    /// 索引统计信息暴露给 UI（设置页等）
    private(set) var indexedCount: Int = 0
    private(set) var totalImagesCount: Int = 0
    var indexingProgress: Double {
        guard totalImagesCount > 0 else { return isLibraryIndexed ? 1.0 : 0.0 }
        return min(1.0, Double(indexedCount) / Double(totalImagesCount))
    }

    /// 特征指纹缓存：磁盘（Core Data）持久层 + 会话级全量内存库
    private lazy var cache = FeaturePrintCache()
    /// 会话级特征库：首次使用时从磁盘一次性全量载入，此后纯内存查询。
    /// 跨线程读写（queryQueue/indexingQueue 写、主线程同步快照读）统一由 storeLock 保护
    private var featureStore: [String: CachedFeature]?
    /// 同步快照备忘：同一会话内同一基准只计算一次（主线程读写，锁保护）
    private var snapshotMemo: [String: [PHAsset]] = [:]
    /// 保护 featureStore / snapshotMemo 的互斥锁
    private let storeLock = NSLock()
    /// 特征管线版本：提取参数或 OS 变更后自动让旧缓存失效
    private static let pipelineVersion = "thumb256-v1|"
        + ProcessInfo.processInfo.operatingSystemVersionString

    static let libraryIndexDidFinishNotification = Notification.Name("PhotoSimilarityMatcher.libraryIndexDidFinish")
    private static let hasBuiltLibraryIndexKey = "PhotoSimilarityMatcher.hasBuiltLibraryIndex"
    private var isBackgroundIndexing = false

    /// 全图库是否已建立过 AI 特征索引（一次扫描，全库所有相簿共同解锁推荐）
    var isLibraryIndexed: Bool {
        get {
            UserDefaults.standard.bool(forKey: Self.hasBuiltLibraryIndexKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.hasBuiltLibraryIndexKey)
        }
    }

    /// 通知有前台用户活跃（如进入详情页、滑动翻页等）：
    /// 后台建库立即暂停，闲置 1.5 秒后自动续跑，彻底消除前台掉帧与抢算力
    func notifyForegroundActivity() {
        activityLock.lock()
        isForegroundActive = true
        foregroundDebounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.activityLock.lock()
            self.isForegroundActive = false
            self.activityLock.unlock()
        }
        foregroundDebounceWorkItem = item
        activityLock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    /// 启动后台静默特征索引构建（低优先级、分批温控让步、主线程零卡顿）
    func startBackgroundIndexingIfNeeded() {
        guard !isLibraryIndexed, !isBackgroundIndexing else { return }
        isBackgroundIndexing = true

        indexingQueue.async { [weak self] in
            guard let self else { return }

            // 1. 相册权限校验
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else {
                self.isBackgroundIndexing = false
                return
            }

            // 2. 获取图库全部图片
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

            var assetsToIndex: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                assetsToIndex.append(asset)
            }

            let total = assetsToIndex.count
            DispatchQueue.main.async {
                self.totalImagesCount = total
            }

            guard total > 0 else {
                self.isLibraryIndexed = true
                self.isBackgroundIndexing = false
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.libraryIndexDidFinishNotification, object: nil)
                }
                return
            }

            self.ensureFeatureStoreLoaded()
            self.updateIndexedCount()

            // 3. 逐批温和提取指纹（每 20 张微歇 50ms，且前台有交互或设备严重发热/低电量时主动挂起）
            var processed = 0
            for asset in assetsToIndex {
                // 前台交互避让：前台正在翻页或浏览详情时，后台静默挂起
                while self.isForegroundActive {
                    self.cache.flush()
                    Thread.sleep(forTimeInterval: 0.2)
                }

                // 设备温控与低电量保护：发热严重或开启低电量模式时挂起
                while ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
                    Thread.sleep(forTimeInterval: 1.0)
                }

                // 若已有有效指纹缓存则直接跳过
                if self.cachedObservation(for: asset) == nil {
                    _ = autoreleasepool {
                        self.cachedOrCompute(asset)
                    }
                }

                processed += 1
                if processed % 20 == 0 {
                    self.cache.flush()
                    self.updateIndexedCount()
                    usleep(50_000) // 50 毫秒温控微让步
                }
            }

            self.cache.flush()
            self.updateIndexedCount()
            self.isLibraryIndexed = true
            self.isBackgroundIndexing = false

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.libraryIndexDidFinishNotification, object: nil)
            }
        }
    }

    private func updateIndexedCount() {
        let count = cache.count(pipelineVersion: Self.pipelineVersion)
        DispatchQueue.main.async {
            self.indexedCount = count
        }
    }

    /// 获取会话内存库中所有可用的 Vision 特征向量快照（用于纯内存毫秒级比对）
    func allCachedObservations() -> [String: VNFeaturePrintObservation] {
        ensureFeatureStoreLoaded()
        storeLock.lock()
        defer { storeLock.unlock() }
        var result: [String: VNFeaturePrintObservation] = [:]
        if let store = featureStore {
            for (id, cached) in store {
                result[id] = cached.observation
            }
        }
        return result
    }

    // MARK: - Public API

    /// 检索与基准照片视觉最相似的 Top N 张。
    ///
    /// - Parameters:
    ///   - base: 基准照片（详情页当前素材）
    ///   - contextAssetIDs: 上下文照片 ID 列表（如来自相簿或当前浏览批次，优先召回）
    ///   - topN: 返回数量上限，默认 12
    ///   - maxDistance: 相似度阈值（特征距离），默认 `defaultMaxDistance`
    ///   - progress: 进度回调（已处理数 / 候选总数），主线程
    ///   - completion: 完成回调（相似度从高到低的结果 + 错误），主线程
    func findSimilar(
        to base: PHAsset,
        contextAssetIDs: [String] = [],
        topN: Int = 12,
        maxDistance: Float = PhotoSimilarityMatcher.defaultMaxDistance,
        progress: @escaping (_ processed: Int, _ total: Int) -> Void = { _, _ in },
        completion: @escaping (_ results: [PHAsset], _ error: Error?) -> Void
    ) {
        notifyForegroundActivity()

        queryQueue.async { [weak self] in
            guard let self else { return }

            let token = UUID()
            self.activeToken = token

            // 1. 相册权限校验
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else {
                self.finish([], MatcherError.photoAccessDenied(status), token: token, completion)
                return
            }

            let baseID = base.localIdentifier

            // 2. 基准特征提取（优先从会话内存/CoreData缓存读取，未命中则单张现场计算 ~30ms）
            guard let basePrint = self.cachedOrCompute(base) else {
                let fallback = self.fastFallbackSimilar(to: base, contextAssetIDs: contextAssetIDs, topN: topN)
                self.finish(fallback, fallback.isEmpty ? MatcherError.baseFeatureUnavailable : nil, token: token, completion)
                return
            }

            // 3. 构建候选池（上下文感知 + 全库已索引库 + 前后3天邻近素材）
            var scored: [(asset: PHAsset, distance: Float)] = []
            var evaluatedIDs = Set<String>([baseID])

            // 3.1 上下文优先候选（若传入了当前相簿/分组的素材 ID 列表）
            if !contextAssetIDs.isEmpty {
                let contextAssets = PHAsset.fetchAssets(withLocalIdentifiers: contextAssetIDs, options: nil)
                contextAssets.enumerateObjects { asset, _, _ in
                    guard asset.localIdentifier != baseID else { return }
                    guard asset.mediaType == .image else { return }
                    evaluatedIDs.insert(asset.localIdentifier)
                    if let print = self.cachedObservation(for: asset) {
                        var distance: Float = .greatestFiniteMagnitude
                        if (try? basePrint.computeDistance(&distance, to: print)) != nil,
                           distance <= maxDistance {
                            scored.append((asset, distance))
                        }
                    }
                }
            }

            // 3.2 全库已索引特征快速检索（纯内存/轻量向量比对，万张只需 < 5ms）
            let allCached = self.allCachedObservations()
            var matchedCachedIDs: [(id: String, distance: Float)] = []
            for (candID, print) in allCached {
                guard !evaluatedIDs.contains(candID) else { continue }
                var distance: Float = .greatestFiniteMagnitude
                if (try? basePrint.computeDistance(&distance, to: print)) != nil,
                   distance <= maxDistance {
                    evaluatedIDs.insert(candID)
                    matchedCachedIDs.append((candID, distance))
                }
            }

            if !matchedCachedIDs.isEmpty {
                let sortedIDs = matchedCachedIDs.sorted { $0.distance < $1.distance }.prefix(topN * 2)
                let fetchedAssets = PHAsset.fetchAssets(withLocalIdentifiers: sortedIDs.map(\.id), options: nil)
                var idMap: [String: PHAsset] = [:]
                fetchedAssets.enumerateObjects { asset, _, _ in
                    idMap[asset.localIdentifier] = asset
                }
                for item in sortedIDs {
                    if let asset = idMap[item.id] {
                        scored.append((asset, item.distance))
                    }
                }
            }

            // 3.3 邻近时间窗口候选（前后 3 天内，最多取 60 张，覆盖连拍与同场景）
            var uncomputedCandidates: [PHAsset] = []
            if let baseDate = base.creationDate {
                let options = PHFetchOptions()
                let startDate = baseDate.addingTimeInterval(-3 * 86400)
                let endDate = baseDate.addingTimeInterval(3 * 86400)
                options.predicate = NSPredicate(
                    format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
                    PHAssetMediaType.image.rawValue, startDate as NSDate, endDate as NSDate
                )
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.fetchLimit = 60

                let nearby = PHAsset.fetchAssets(with: options)
                nearby.enumerateObjects { asset, _, _ in
                    guard !evaluatedIDs.contains(asset.localIdentifier) else { return }
                    evaluatedIDs.insert(asset.localIdentifier)
                    if let print = self.cachedObservation(for: asset) {
                        var distance: Float = .greatestFiniteMagnitude
                        if (try? basePrint.computeDistance(&distance, to: print)) != nil,
                           distance <= maxDistance {
                            scored.append((asset, distance))
                        }
                    } else {
                        uncomputedCandidates.append(asset)
                    }
                }
            }

            // 3.4 允许对邻近未索引候选进行小额现算（上限 25 张，耗时数百毫秒内）
            let maxOnDemand = 25
            for asset in uncomputedCandidates.prefix(maxOnDemand) {
                if self.activeToken != token {
                    self.finish([], MatcherError.cancelled, token: token, completion)
                    return
                }
                if let print = autoreleasepool(invoking: { self.cachedOrCompute(asset) }) {
                    var distance: Float = .greatestFiniteMagnitude
                    if (try? basePrint.computeDistance(&distance, to: print)) != nil,
                       distance <= maxDistance {
                        scored.append((asset, distance))
                    }
                }
            }

            // 4. 排序并取 Top N
            let results = Array(scored
                .sorted { $0.distance < $1.distance }
                .prefix(max(0, topN))
                .map(\.asset)
                .filter { $0.localIdentifier != baseID })

            // 5. 冷启动兜底：若全库尚未建好索引且结果为空，用 fastFallbackSimilar 0ms 呈现连拍/相似
            if results.isEmpty && !self.isLibraryIndexed {
                let fallback = self.fastFallbackSimilar(to: base, contextAssetIDs: contextAssetIDs, topN: topN)
                if !fallback.isEmpty {
                    self.storeLock.lock()
                    self.snapshotMemo[baseID] = fallback
                    self.storeLock.unlock()
                    self.finish(fallback, nil, token: token, completion)
                    return
                }
            }

            self.storeLock.lock()
            self.snapshotMemo[baseID] = results
            self.storeLock.unlock()

            self.finish(results, nil, token: token, completion)
        }
    }

    /// 冷启动极速兜底：针对全库 Vision 索引尚未建立阶段，利用拍摄时间前后 60 秒与快速差值哈希（dHash）
    /// 在 5~10 毫秒内秒级召回连拍与同场景素材，作为首屏占位
    func fastFallbackSimilar(
        to base: PHAsset,
        contextAssetIDs: [String] = [],
        topN: Int = 12
    ) -> [PHAsset] {
        let baseID = base.localIdentifier
        guard let baseDate = base.creationDate else { return [] }

        // 1. 取前后 60 秒内的同场景/连拍照片候选（最多 25 张）
        let options = PHFetchOptions()
        let startDate = baseDate.addingTimeInterval(-60)
        let endDate = baseDate.addingTimeInterval(60)
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaType.image.rawValue, startDate as NSDate, endDate as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 25

        let nearby = PHAsset.fetchAssets(with: options)
        var candidates: [PHAsset] = []
        nearby.enumerateObjects { asset, _, _ in
            if asset.localIdentifier != baseID {
                candidates.append(asset)
            }
        }

        guard !candidates.isEmpty else { return [] }

        // 2. 快速差值哈希比对（单张仅 ~0.2ms，20 张总耗时 < 5ms）
        let baseHash = computeQuickDHash(for: base)
        guard !baseHash.isEmpty else { return Array(candidates.prefix(topN)) }

        var matched: [(asset: PHAsset, distance: Int)] = []
        for cand in candidates {
            let candHash = computeQuickDHash(for: cand)
            guard !candHash.isEmpty else { continue }
            let dist = hammingDistance(baseHash, candHash)
            if dist <= 14 {
                matched.append((cand, dist))
            }
        }

        if matched.isEmpty {
            return candidates.filter { abs($0.creationDate?.timeIntervalSince(baseDate) ?? 999) <= 15 }
        }

        return matched.sorted { $0.distance < $1.distance }.prefix(topN).map(\.asset)
    }

    private func computeQuickDHash(for asset: PHAsset) -> String {
        let options = PHImageRequestOptions()
        options.resizeMode = .fast
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true

        var hash = ""
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 64, height: 64),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image = image else { return }
            let width = 9
            let height = 8
            let colorSpace = CGColorSpaceCreateDeviceGray()
            guard let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }

            UIGraphicsPushContext(context)
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1.0, y: -1.0)
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()

            guard let pixelData = context.data else { return }
            let pixels = pixelData.bindMemory(to: UInt8.self, capacity: width * height)

            for row in 0..<height {
                for col in 0..<(width - 1) {
                    let left = Int(pixels[row * width + col])
                    let right = Int(pixels[row * width + col + 1])
                    hash += left < right ? "1" : "0"
                }
            }
        }
        return hash
    }

    private func hammingDistance(_ a: String, _ b: String) -> Int {
        guard a.count == b.count else { return 64 }
        var dist = 0
        let aChars = Array(a)
        let bChars = Array(b)
        for i in 0..<aChars.count {
            if aChars[i] != bChars[i] { dist += 1 }
        }
        return dist
    }

    /// 同步缓存快照：供详情页初始化时使用，使相关照片区与页面首帧同在。
    /// 主线程调用；备忘命中零开销，未命中时在内存库上计算（小库毫秒级，
    /// 特征库未载入时返回 nil，由 prewarm 兜底）。返回数组可能为空（无过阈值候选）
    func cachedSnapshotSync(
        to base: PHAsset,
        topN: Int = 12,
        maxDistance: Float = PhotoSimilarityMatcher.defaultMaxDistance
    ) -> [PHAsset]? {
        let baseID = base.localIdentifier
        storeLock.lock()
        defer { storeLock.unlock() }
        return snapshotMemo[baseID]
    }

    /// 缓存快照：仅用已缓存的指纹计算相似结果（零图像解码、零 Vision 计算）。
    /// 基准无有效缓存时返回 nil（该照片从未扫描过），调用方回退全量扫描；
    /// 用于进入详情页时立即上屏上次结果，不出骨架屏
    func cachedSnapshot(
        to base: PHAsset,
        topN: Int = 12,
        maxDistance: Float = PhotoSimilarityMatcher.defaultMaxDistance
    ) async -> [PHAsset]? {
        await withCheckedContinuation { continuation in
            queryQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let baseID = base.localIdentifier
                self.storeLock.lock()
                if let memo = self.snapshotMemo[baseID] {
                    self.storeLock.unlock()
                    continuation.resume(returning: memo)
                    return
                }
                self.storeLock.unlock()

                guard let basePrint = self.cachedObservation(for: base) else {
                    continuation.resume(returning: nil)
                    return
                }

                let allCached = self.allCachedObservations()
                var scored: [(id: String, distance: Float)] = []
                for (candID, print) in allCached where candID != baseID {
                    var distance: Float = .greatestFiniteMagnitude
                    if (try? basePrint.computeDistance(&distance, to: print)) != nil,
                       distance <= maxDistance {
                        scored.append((candID, distance))
                    }
                }

                let topIDs = scored.sorted { $0.distance < $1.distance }.prefix(max(0, topN)).map(\.id)
                guard !topIDs.isEmpty else {
                    self.storeLock.lock()
                    self.snapshotMemo[baseID] = []
                    self.storeLock.unlock()
                    continuation.resume(returning: [])
                    return
                }

                let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(topIDs), options: nil)
                var idToAsset: [String: PHAsset] = [:]
                assets.enumerateObjects { asset, _, _ in
                    idToAsset[asset.localIdentifier] = asset
                }
                let results = topIDs.compactMap { idToAsset[$0] }

                self.storeLock.lock()
                self.snapshotMemo[baseID] = results
                self.storeLock.unlock()
                continuation.resume(returning: results)
            }
        }
    }

    /// 取消进行中的单张素材检索：
    /// 在跑任务会尽快以 `.cancelled` 错误回调，后续新检索立即获得队列
    func cancel() {
        queryQueue.async { [weak self] in
            self?.activeToken = nil
            self?.cache.flush()
        }
    }

    // MARK: - Album Matching API

    /// 检索与相簿现有素材视觉相符的照片（用于相簿二级页「更多适合这个相簿的照片」）。
    ///
    /// - Parameters:
    ///   - albumAssets: 当前相簿已有照片集合（提取前 20 张作为基准特征）
    ///   - excludingIDs: 需排除的 localIdentifier（包括当前相簿已有、待删除废纸篓等）
    ///   - topN: 返回数量上限，默认 24
    ///   - maxDistance: 相似度阈值（特征距离），默认 `defaultMaxDistance`
    ///   - progress: 进度回调（已处理数 / 候选总数），主线程
    ///   - completion: 完成回调（相似度从高到低的结果 + 错误），主线程
    /// 检索与相簿现有素材视觉相符的照片（用于相簿二级页「更多适合这个相簿的照片」）。
    ///
    /// - Parameters:
    ///   - albumAssets: 当前相簿已有照片集合（提取代表性图片作为基准特征）
    ///   - excludingIDs: 需排除的 localIdentifier（包括当前相簿已有、待删除废纸篓等）
    ///   - topN: 返回数量上限，默认 30
    ///   - maxDistance: 相似度阈值（特征距离），默认 `defaultAlbumMaxDistance` (0.72)
    ///   - progress: 进度回调（已处理数 / 候选总数），主线程
    ///   - completion: 完成回调（相似度从高到低的结果 + 错误），主线程
    func findSimilar(
        toAlbumAssets albumAssets: [PHAsset],
        excludingIDs: Set<String>,
        topN: Int = 30,
        maxDistance: Float = PhotoSimilarityMatcher.defaultAlbumMaxDistance,
        progress: @escaping (_ processed: Int, _ total: Int) -> Void = { _, _ in },
        completion: @escaping (_ results: [PHAsset], _ error: Error?) -> Void
    ) {
        notifyForegroundActivity()

        queryQueue.async { [weak self] in
            guard let self else { return }

            let token = UUID()
            self.albumActiveToken = token

            // 1. 相册权限校验
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else {
                self.finishAlbum([], MatcherError.photoAccessDenied(status), token: token, completion)
                return
            }

            // 2. 基准特征提取：优先过滤图片类型（排除视频等不可直接提取的素材）
            let imageAssets = albumAssets.filter { $0.mediaType == .image }
            let candidateBaseAssets = imageAssets.isEmpty ? albumAssets : imageAssets
            guard !candidateBaseAssets.isEmpty else {
                self.finishAlbum([], nil, token: token, completion)
                return
            }

            var basePrints: [VNFeaturePrintObservation] = []
            for asset in candidateBaseAssets {
                if let print = self.cachedOrCompute(asset) ?? self.computeFeaturePrintWithNetworkFallback(for: asset) {
                    basePrints.append(print)
                    if basePrints.count >= 20 { break }
                }
            }

            guard !basePrints.isEmpty else {
                self.finishAlbum([], MatcherError.baseFeatureUnavailable, token: token, completion)
                return
            }

            // 3. 候选收集：全相册图片
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

            var candidates: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                guard !excludingIDs.contains(asset.localIdentifier) else { return }
                candidates.append(asset)
            }

            let total = candidates.count
            guard total > 0 else {
                self.finishAlbum([], nil, token: token, completion)
                return
            }

            // 智能多级候选排序：
            // 1. 相簿时间窗口（相簿照片拍摄前后 14 天内的素材）优先级最高（最可能遗落同批照片）
            // 2. 已有特征缓存（内存/CoreData）零计算素材次之
            // 3. 全库其余素材按创建时间倒序排
            let albumDates = albumAssets.compactMap(\.creationDate)
            let minWindow = albumDates.min()?.addingTimeInterval(-14 * 86400)
            let maxWindow = albumDates.max()?.addingTimeInterval(14 * 86400)

            candidates.sort { a, b in
                let aDate = a.creationDate ?? .distantPast
                let bDate = b.creationDate ?? .distantPast
                let aInWindow = (minWindow != nil && maxWindow != nil && aDate >= minWindow! && aDate <= maxWindow!)
                let bInWindow = (minWindow != nil && maxWindow != nil && bDate >= minWindow! && bDate <= maxWindow!)
                if aInWindow != bInWindow { return aInWindow }

                let aCached = self.cachedObservation(for: a) != nil
                let bCached = self.cachedObservation(for: b) != nil
                if aCached != bCached { return aCached }

                return aDate > bDate
            }

            // 4. 逐一比对：计算候选素材与相簿各基准特征的最小距离
            // 分两阶段：Phase 1 优先纯内存比对已缓存指纹；Phase 2 计算新素材
            var scored: [(asset: PHAsset, distance: Float)] = []
            var processed = 0
            var uncomputedCount = 0
            let maxUncomputedScan = 40 // 限制未索引图片的最大扫描张数，避免前台卡顿

            for asset in candidates {
                if self.albumActiveToken != token {
                    self.finishAlbum([], MatcherError.cancelled, token: token, completion)
                    return
                }

                // 尝试从内存/CoreData直接取
                let isCached = self.cachedObservation(for: asset) != nil
                if !isCached {
                    uncomputedCount += 1
                    // 如果已经获取到足够多极佳匹配且未索引素材过多，可提早收敛
                    if scored.count >= topN * 2 && uncomputedCount > 15 {
                        break
                    }
                    if uncomputedCount > maxUncomputedScan {
                        break
                    }
                }

                if let candidatePrint = autoreleasepool(invoking: { self.cachedOrCompute(asset) }) {
                    var minDistance: Float = .greatestFiniteMagnitude
                    for basePrint in basePrints {
                        var distance: Float = .greatestFiniteMagnitude
                        if (try? basePrint.computeDistance(&distance, to: candidatePrint)) != nil {
                            if distance < minDistance {
                                minDistance = distance
                            }
                        }
                    }

                    if minDistance <= maxDistance {
                        scored.append((asset, minDistance))
                    }
                }

                processed += 1
                if processed % Self.progressStride == 0 || processed == total {
                    let done = processed
                    DispatchQueue.main.async { progress(done, total) }
                }
            }

            // 循环结束：派发满进度回报（覆盖提前收敛退出的情况，保证进度条平滑拉满）
            DispatchQueue.main.async { progress(total, total) }

            // 5. 排序取前 topN（按距离升序，越近越相关）
            let results = Array(scored
                .sorted { $0.distance < $1.distance }
                .prefix(max(0, topN))
                .map(\.asset)
                .filter { !excludingIDs.contains($0.localIdentifier) })

            self.finishAlbum(results, nil, token: token, completion)
        }
    }

    /// 异步获取相簿相似推荐照片（支持进度回调）
    func findSimilar(
        toAlbumAssets albumAssets: [PHAsset],
        excludingIDs: Set<String>,
        topN: Int = 30,
        maxDistance: Float = PhotoSimilarityMatcher.defaultAlbumMaxDistance,
        onProgress: ((_ processed: Int, _ total: Int) -> Void)? = nil
    ) async throws -> [PHAsset] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                findSimilar(
                    toAlbumAssets: albumAssets,
                    excludingIDs: excludingIDs,
                    topN: topN,
                    maxDistance: maxDistance,
                    progress: { processed, total in
                        onProgress?(processed, total)
                    }
                ) { assets, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: assets)
                    }
                }
            }
        } onCancel: {
            self.cancelAlbumSearch()
        }
    }

    /// 建立全图库 AI 特征索引并检索当前相簿的相似照片推荐（支持进度回调，一次构建全库受益）
    func indexLibraryAndFindSimilar(
        toAlbumAssets albumAssets: [PHAsset],
        excludingIDs: Set<String>,
        topN: Int = 30,
        maxDistance: Float = PhotoSimilarityMatcher.defaultAlbumMaxDistance,
        onProgress: ((_ processed: Int, _ total: Int) -> Void)? = nil
    ) async throws -> [PHAsset] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                indexLibraryAndFindSimilar(
                    toAlbumAssets: albumAssets,
                    excludingIDs: excludingIDs,
                    topN: topN,
                    maxDistance: maxDistance,
                    progress: { processed, total in
                        onProgress?(processed, total)
                    }
                ) { assets, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: assets)
                    }
                }
            }
        } onCancel: {
            self.cancelAlbumSearch()
        }
    }

    /// 建立全图库 AI 特征索引并检索当前相簿的相似照片推荐（底层实现）
    func indexLibraryAndFindSimilar(
        toAlbumAssets albumAssets: [PHAsset],
        excludingIDs: Set<String>,
        topN: Int = 30,
        maxDistance: Float = PhotoSimilarityMatcher.defaultAlbumMaxDistance,
        progress: @escaping (_ processed: Int, _ total: Int) -> Void = { _, _ in },
        completion: @escaping (_ results: [PHAsset], _ error: Error?) -> Void
    ) {
        notifyForegroundActivity()

        queryQueue.async { [weak self] in
            guard let self else { return }

            let token = UUID()
            self.albumActiveToken = token

            // 1. 权限校验
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else {
                self.finishAlbum([], MatcherError.photoAccessDenied(status), token: token, completion)
                return
            }

            // 2. 基准特征提取
            let imageAssets = albumAssets.filter { $0.mediaType == .image }
            let candidateBaseAssets = imageAssets.isEmpty ? albumAssets : imageAssets
            guard !candidateBaseAssets.isEmpty else {
                self.finishAlbum([], nil, token: token, completion)
                return
            }

            var basePrints: [VNFeaturePrintObservation] = []
            for asset in candidateBaseAssets {
                if let print = self.cachedOrCompute(asset) ?? self.computeFeaturePrintWithNetworkFallback(for: asset) {
                    basePrints.append(print)
                    if basePrints.count >= 20 { break }
                }
            }

            guard !basePrints.isEmpty else {
                self.finishAlbum([], MatcherError.baseFeatureUnavailable, token: token, completion)
                return
            }

            // 3. 全库图片获取
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

            var allCandidates: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                allCandidates.append(asset)
            }

            let total = allCandidates.count
            guard total > 0 else {
                self.isLibraryIndexed = true
                self.finishAlbum([], nil, token: token, completion)
                return
            }

            // 4. 遍历全库建立特征索引并同时计算当前相簿相似度
            var scored: [(asset: PHAsset, distance: Float)] = []
            var processed = 0

            for asset in allCandidates {
                if self.albumActiveToken != token {
                    self.finishAlbum([], MatcherError.cancelled, token: token, completion)
                    return
                }

                // 提取并缓存特征（写通内存库与 Core Data）
                if let candidatePrint = autoreleasepool(invoking: { self.cachedOrCompute(asset) }) {
                    // 若不是被排除的素材，计算与当前相簿基准特征的距离
                    if !excludingIDs.contains(asset.localIdentifier) {
                        var minDistance: Float = .greatestFiniteMagnitude
                        for basePrint in basePrints {
                            var distance: Float = .greatestFiniteMagnitude
                            if (try? basePrint.computeDistance(&distance, to: candidatePrint)) != nil {
                                if distance < minDistance {
                                    minDistance = distance
                                }
                            }
                        }

                        if minDistance <= maxDistance {
                            scored.append((asset, minDistance))
                        }
                    }
                }

                processed += 1
                if processed % Self.progressStride == 0 || processed == total {
                    let done = processed
                    DispatchQueue.main.async { progress(done, total) }
                }
            }

            // 标记全库索引已完成
            self.isLibraryIndexed = true

            // 派发 100% 满进度
            DispatchQueue.main.async { progress(total, total) }

            // 5. 排序取前 topN
            let results = Array(scored
                .sorted { $0.distance < $1.distance }
                .prefix(max(0, topN))
                .map(\.asset)
                .filter { !excludingIDs.contains($0.localIdentifier) })

            self.finishAlbum(results, nil, token: token, completion)
        }
    }

    /// 取消进行中的相簿相似推荐检索
    nonisolated func cancelAlbumSearch() {
        queryQueue.async { [weak self] in
            self?.albumActiveToken = nil
            self?.cache.flush()
        }
    }

    // MARK: - Private

    /// 相簿检索统一完成出口
    private func finishAlbum(
        _ results: [PHAsset],
        _ error: Error?,
        token: UUID,
        _ completion: @escaping ([PHAsset], Error?) -> Void
    ) {
        cache.flush()
        if error == nil, albumActiveToken != token { return }
        DispatchQueue.main.async { completion(results, error) }
    }

    /// 统一完成出口：每次调用保证回调一次。
    /// 「正常完成但令牌已被取代」时静默丢弃（新检索已接管结果语义），
    /// 「取消/失败」路径始终回调，让调用方能清理 loading 态
    private func finish(
        _ results: [PHAsset],
        _ error: Error?,
        token: UUID,
        _ completion: @escaping ([PHAsset], Error?) -> Void
    ) {
        cache.flush()
        if error == nil, activeToken != token { return }
        DispatchQueue.main.async { completion(results, error) }
    }

    /// 取特征：会话特征库命中即用（零反序列化）；未命中现算并写通内存库与磁盘
    private func cachedOrCompute(_ asset: PHAsset) -> VNFeaturePrintObservation? {
        if let hit = cachedObservation(for: asset) {
            return hit
        }
        guard let observation = featurePrint(for: asset) else { return nil }
        remember(observation, for: asset)
        return observation
    }

    /// 会话特征库查询：素材被编辑过（modificationDate 变化）视为失效。
    /// 支持二级缓存：内存未命中时按需从 Core Data 磁盘读取并写回内存 LRU
    private func cachedObservation(for asset: PHAsset) -> VNFeaturePrintObservation? {
        ensureFeatureStoreLoaded()
        storeLock.lock()
        if let feature = featureStore?[asset.localIdentifier],
           feature.modificationDate == asset.modificationDate {
            storeLock.unlock()
            return feature.observation
        }
        storeLock.unlock()

        // 二级缓存兜底：从 Core Data 磁盘持久层按需读取（内存占用极低）
        if let observation = cache.loadObservation(for: asset, pipelineVersion: Self.pipelineVersion) {
            rememberInMemoryOnly(observation, for: asset)
            return observation
        }

        return nil
    }

    /// 仅写入内存字典（LRU 淘汰），不再重复写磁盘
    private func rememberInMemoryOnly(_ observation: VNFeaturePrintObservation, for asset: PHAsset) {
        storeLock.lock()
        if featureStore?.count ?? 0 >= Self.maxSessionFeatureCount,
           let evicted = featureStore?.keys.first {
            featureStore?.removeValue(forKey: evicted)
        }
        featureStore?[asset.localIdentifier] = CachedFeature(
            observation: observation,
            modificationDate: asset.modificationDate
        )
        storeLock.unlock()
    }

    /// 写入会话特征库并持久化到磁盘（写通：扫描中断不丢已完成部分）。
    /// 内存库超过容量上限时先淘汰任意条目再写入，防超大相册全量常驻内存
    private func remember(_ observation: VNFeaturePrintObservation, for asset: PHAsset) {
        rememberInMemoryOnly(observation, for: asset)
        cache.store(observation, for: asset, pipelineVersion: Self.pipelineVersion)
    }

    /// 首次使用时从磁盘全量载入指纹（一次 IO + 反序列化，此后会话内零开销）。
    /// 载入后清空快照备忘（数据基线变化，旧快照作废）
    private func ensureFeatureStoreLoaded() {
        storeLock.lock()
        if featureStore != nil {
            storeLock.unlock()
            return
        }
        storeLock.unlock()

        var store: [String: CachedFeature] = [:]
        for (identifier, modificationDate, data) in cache.loadAll(pipelineVersion: Self.pipelineVersion) {
            // 超出会话库容量即停止装载（磁盘缓存保留全量，仅限制内存驻留）
            if store.count >= Self.maxSessionFeatureCount { break }
            if let observation = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self, from: data
            ) {
                store[identifier] = CachedFeature(
                    observation: observation,
                    modificationDate: modificationDate
                )
            }
        }

        storeLock.lock()
        featureStore = store
        snapshotMemo.removeAll()
        storeLock.unlock()
    }

    /// 启动预热：提前把磁盘指纹载入内存库，详情页初始化时的同步快照即为纯内存查询
    func prewarm() {
        queryQueue.async { [weak self] in
            self?.ensureFeatureStoreLoaded()
            self?.updateIndexedCount()
        }
    }

    /// 提取单张照片的视觉特征指纹（本地缩略图方案）。
    ///
    /// 本地性约束：`isNetworkAccessAllowed = false` 始终关闭，绝不触发云端下载。
    /// 关键在 deliveryMode 用 opportunistic + 小尺寸请求：Photos 的缩略图缓存
    /// 在 iCloud 优化存储下依然本地可用；highQualityFormat 会对原片缺失的
    /// 素材整体失败（真机列表空白的根因），opportunistic 则返回本地降级图
    private func featurePrint(for asset: PHAsset) -> VNFeaturePrintObservation? {
        // 主尺寸取不到再降级小尺寸（两级都命中本地缓存，无网络路径）
        guard let cgImage = localThumbnail(of: asset, maxPixel: Self.inputPixelSize)
            ?? localThumbnail(of: asset, maxPixel: Self.fallbackPixelSize) else {
            return nil
        }

        // Espresso 上下文创建在模拟器上偶发失败（NSOSStatusErrorDomain -1），
        // 短退避重试可恢复；连续失败才放弃该图
        for attempt in 0..<3 {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNGenerateImageFeaturePrintRequest()
            // 模拟器上 GPU/ANE 的 Espresso 上下文创建不稳定（NSOSStatus -1），
            // 强制 CPU 推理保证可用；真机保持默认加速路径
            #if targetEnvironment(simulator)
            if let cpuDevice = Self.cpuComputeDevice() {
                request.setComputeDevice(cpuDevice, for: .main)
            }
            #endif
            do {
                try handler.perform([request])
                return request.results?.first as? VNFeaturePrintObservation
            } catch {
                if attempt < 2 {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
        return nil
    }

    /// 模拟器专用：从 CoreML 设备列表取 CPU 设备（VNRequest.usesCPUOnly 自 iOS 17 弃用后的等价写法）
    #if targetEnvironment(simulator)
    private static func cpuComputeDevice() -> MLComputeDevice? {
        MLComputeDevice.allComputeDevices.first { device in
            if case .cpu = device { return true }
            return false
        }
    }
    #endif

    /// 同步读取本地缩略图（禁网）：有则返回（可能是降级图，特征提取足够用），
    /// 本地完全无图时返回 nil
    private func localThumbnail(of asset: PHAsset, maxPixel: CGFloat) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false
        options.resizeMode = .fast

        var cgImage: CGImage?
        _ = autoreleasepool {
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: maxPixel, height: maxPixel),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                cgImage = image?.cgImage
            }
        }
        return cgImage
    }

    /// 针对样本图的网络缩略图兜底（解决 iCloud 未全量下载时的样本缺失问题）
    func computeFeaturePrintWithNetworkFallback(for asset: PHAsset) -> VNFeaturePrintObservation? {
        guard let cgImage = localThumbnail(of: asset, maxPixel: Self.inputPixelSize)
            ?? thumbnailWithNetworkAllowed(of: asset, maxPixel: Self.inputPixelSize) else {
            return nil
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        #if targetEnvironment(simulator)
        if let cpuDevice = Self.cpuComputeDevice() {
            request.setComputeDevice(cpuDevice, for: .main)
        }
        #endif
        do {
            try handler.perform([request])
            if let observation = request.results?.first as? VNFeaturePrintObservation {
                remember(observation, for: asset)
                return observation
            }
        } catch {}
        return nil
    }

    private func thumbnailWithNetworkAllowed(of asset: PHAsset, maxPixel: CGFloat) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        var cgImage: CGImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: maxPixel, height: maxPixel),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            cgImage = image?.cgImage
        }
        return cgImage
    }
}

// MARK: - Cached Feature（会话内存条目）
private struct CachedFeature {
    let observation: VNFeaturePrintObservation
    let modificationDate: Date?
}

// MARK: - FeaturePrintCache（特征指纹持久缓存）
/// localIdentifier → VNFeaturePrintObservation 序列化数据 的 Core Data 持久层。
/// 命中条件：素材未编辑（modificationDate 一致）且管线版本一致。
/// matcher 的串行队列上调用，天然串行；后台 context 自带队列，performAndWait 保证线程安全
private final class FeaturePrintCache {

    private lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(
            name: "PhotoSimilarityMatcherCache",
            managedObjectModel: Self.managedObjectModel
        )
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        let description = NSPersistentStoreDescription(
            url: appSupportURL.appendingPathComponent("PhotoSimilarityMatcherCache.sqlite")
        )
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error = error {
                print("FeaturePrintCache store load failed: \(error)")
            }
        }
        return container
    }()

    private lazy var context: NSManagedObjectContext = {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()

    private let batchSize = 50
    private var pendingCount = 0

    /// 全量读取当前管线版本的指纹（identifier, modificationDate, data）。
    /// 供会话启动时一次性载入内存，此后查询不再触库
    func loadAll(pipelineVersion: String) -> [(identifier: String,
                                               modificationDate: Date?,
                                               data: Data)] {
        var results: [(String, Date?, Data)] = []
        context.performAndWait {
            let request = CachedFeaturePrint.fetchRequest()
            request.predicate = NSPredicate(
                format: "pipelineVersion == %@", pipelineVersion
            )
            request.fetchBatchSize = 500
            for record in (try? context.fetch(request)) ?? [] {
                results.append((record.localIdentifier,
                                record.modificationDate,
                                record.featureData))
            }
            // 关键：读取完后立即释放查询出的托管对象与快照内存
            self.context.reset()
        }
        return results
    }

    /// 写入/更新缓存（分批批量写入 + 内存复位，避免逐张刷盘且锁定内存恒定 < 20MB）
    func store(_ observation: VNFeaturePrintObservation,
               for asset: PHAsset,
               pipelineVersion: String) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: observation, requiringSecureCoding: true
        ), !data.isEmpty else { return }
        let identifier = asset.localIdentifier
        let modificationDate = asset.modificationDate
        context.performAndWait {
            let request = CachedFeaturePrint.fetchRequest()
            request.predicate = NSPredicate(
                format: "localIdentifier == %@ AND pipelineVersion == %@",
                identifier, pipelineVersion
            )
            request.fetchLimit = 1
            let record = (try? context.fetch(request))?.first ?? {
                let record = CachedFeaturePrint(context: self.context)
                record.localIdentifier = identifier
                record.pipelineVersion = pipelineVersion
                return record
            }()
            record.featureData = data
            record.modificationDate = modificationDate
            record.computedAt = Date()

            self.pendingCount += 1
            if self.pendingCount >= self.batchSize {
                try? self.context.save()
                self.context.reset()
                self.pendingCount = 0
            }
        }
    }

    /// 提交当前未满批次的改动，并清空上下文内存
    func flush() {
        context.performAndWait {
            if self.pendingCount > 0 || self.context.hasChanges {
                try? self.context.save()
            }
            self.context.reset()
            self.pendingCount = 0
        }
    }

    /// 获取指定管线版本的已缓存指纹总数
    func count(pipelineVersion: String) -> Int {
        var total = 0
        context.performAndWait {
            let request = CachedFeaturePrint.fetchRequest()
            request.predicate = NSPredicate(
                format: "pipelineVersion == %@", pipelineVersion
            )
            total = (try? self.context.count(for: request)) ?? 0
        }
        return total
    }

    /// 从磁盘单条读取指定资产的特征指纹（用于二级缓存兜底，读完即释放）
    func loadObservation(for asset: PHAsset, pipelineVersion: String) -> VNFeaturePrintObservation? {
        var observation: VNFeaturePrintObservation?
        let identifier = asset.localIdentifier
        context.performAndWait {
            let request = CachedFeaturePrint.fetchRequest()
            request.predicate = NSPredicate(
                format: "localIdentifier == %@ AND pipelineVersion == %@",
                identifier, pipelineVersion
            )
            request.fetchLimit = 1
            if let record = (try? context.fetch(request))?.first,
               let obs = try? NSKeyedUnarchiver.unarchivedObject(
                   ofClass: VNFeaturePrintObservation.self,
                   from: record.featureData
               ) {
                observation = obs
            }
            self.context.reset()
        }
        return observation
    }

    // MARK: - Core Data Model (programmatic)

    private static let managedObjectModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "CachedFeaturePrint"
        entity.managedObjectClassName = "CachedFeaturePrint"

        let localId = NSAttributeDescription()
        localId.name = "localIdentifier"
        localId.attributeType = .stringAttributeType
        localId.isOptional = false

        let featureData = NSAttributeDescription()
        featureData.name = "featureData"
        featureData.attributeType = .binaryDataAttributeType
        featureData.isOptional = false

        let modificationDate = NSAttributeDescription()
        modificationDate.name = "modificationDate"
        modificationDate.attributeType = .dateAttributeType
        modificationDate.isOptional = true

        let pipelineVersion = NSAttributeDescription()
        pipelineVersion.name = "pipelineVersion"
        pipelineVersion.attributeType = .stringAttributeType
        pipelineVersion.isOptional = false

        let computedAt = NSAttributeDescription()
        computedAt.name = "computedAt"
        computedAt.attributeType = .dateAttributeType
        computedAt.isOptional = false

        entity.properties = [localId, featureData, modificationDate, pipelineVersion, computedAt]
        model.entities = [entity]
        return model
    }()
}

// MARK: - Cached Feature Print Object

@objc(CachedFeaturePrint)
final class CachedFeaturePrint: NSManagedObject {
    @NSManaged public var localIdentifier: String
    @NSManaged public var featureData: Data
    @NSManaged public var modificationDate: Date?
    @NSManaged public var pipelineVersion: String
    @NSManaged public var computedAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<CachedFeaturePrint> {
        return NSFetchRequest<CachedFeaturePrint>(entityName: "CachedFeaturePrint")
    }
}
