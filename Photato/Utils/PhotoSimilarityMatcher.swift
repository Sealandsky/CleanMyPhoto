import Foundation
import Photos
import UIKit
import Vision
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
    /// 特征提取的缩略图边长：256px 直接命中本地缩略图缓存（iCloud 优化存储下
    /// 无需下载原图），基准与候选统一尺寸保证特征距离可比
    private static let inputPixelSize: CGFloat = 256
    /// 主尺寸取不到时的兜底边长（覆盖极端无中等缩略图的素材）
    private static let fallbackPixelSize: CGFloat = 160
    /// 进度回报节流步长：每处理 N 张向主线程回报一次（大相册防主线程刷屏）
    private static let progressStride = 10

    // MARK: - Threading

    /// 串行计算队列：任务天然排队执行，避免并发扫描造成内存峰值与 CPU 争抢
    private let workQueue = DispatchQueue(label: "cn.bryan.photato.similarity-matcher", qos: .userInitiated)
    /// 当前有效任务令牌：仅在 workQueue 上读写（线程 confinement 保证安全）
    private var activeToken: UUID?

    /// 特征指纹缓存：磁盘（Core Data）持久层 + 会话级全量内存库
    private lazy var cache = FeaturePrintCache()
    /// 会话级特征库：首次使用时从磁盘一次性全量载入，此后纯内存查询。
    /// 跨线程读写（workQueue 写、主线程同步快照读）统一由 storeLock 保护
    private var featureStore: [String: CachedFeature]?
    /// 同步快照备忘：同一会话内同一基准只计算一次（主线程读写，锁保护）
    private var snapshotMemo: [String: [PHAsset]] = [:]
    /// 保护 featureStore / snapshotMemo 的互斥锁
    private let storeLock = NSLock()
    /// 特征管线版本：提取参数或 OS 变更后自动让旧缓存失效
    private static let pipelineVersion = "thumb256-v1|"
        + ProcessInfo.processInfo.operatingSystemVersionString

    // MARK: - Public API

    /// 检索与基准照片视觉最相似的 Top N 张。
    ///
    /// - Parameters:
    ///   - base: 基准照片（详情页当前素材）
    ///   - topN: 返回数量上限，默认 12
    ///   - maxDistance: 相似度阈值（特征距离），默认 `defaultMaxDistance`
    ///   - progress: 进度回调（已处理数 / 候选总数），主线程
    ///   - completion: 完成回调（相似度从高到低的结果 + 错误），主线程；
    ///     每次调用保证回调且仅回调一次，任何失败路径 results 均为空数组
    func findSimilar(
        to base: PHAsset,
        topN: Int = 12,
        maxDistance: Float = PhotoSimilarityMatcher.defaultMaxDistance,
        progress: @escaping (_ processed: Int, _ total: Int) -> Void = { _, _ in },
        completion: @escaping (_ results: [PHAsset], _ error: Error?) -> Void
    ) {
        workQueue.async { [weak self] in
            guard let self else { return }

            let token = UUID()
            self.activeToken = token

            // 1. 相册权限校验（查询 .readWrite 级别，已授权该级别及以上才放行）
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else {
                self.finish([], MatcherError.photoAccessDenied(status), token: token, completion)
                return
            }

            // 2. 基准特征提取（缓存命中则零计算）：失败即整体失败（没有可比较的锚点）
            guard let basePrint = self.cachedOrCompute(base) else {
                self.finish([], MatcherError.baseFeatureUnavailable, token: token, completion)
                return
            }

            // 3. 候选收集：全相册图片，枚举时排除基准自身
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

            let baseID = base.localIdentifier
            var candidates: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                // 【强制】排除基准照片（第一重）：localIdentifier 精确匹配
                guard asset.localIdentifier != baseID else { return }
                candidates.append(asset)
            }

            let total = candidates.count
            guard total > 0 else {
                self.finish([], nil, token: token, completion)
                return
            }

            // 4. 逐候选提取特征并计算距离（同步图像请求要求在后台线程，此处满足）
            var scored: [(asset: PHAsset, distance: Float)] = []
            var processed = 0
            for asset in candidates {
                // 任务被取消 / 被新一轮检索取代：立即终止本轮回调 .cancelled
                if self.activeToken != token {
                    self.finish([], MatcherError.cancelled, token: token, completion)
                    return
                }

                // 单张失败仅跳过（连本地缩略图都没有 / 数据损坏），不中断整体
                if let print = autoreleasepool(invoking: { self.cachedOrCompute(asset) }) {
                    var distance: Float = .greatestFiniteMagnitude
                    if (try? basePrint.computeDistance(&distance, to: print)) != nil,
                       distance <= maxDistance {
                        scored.append((asset, distance))
                    }
                }

                processed += 1
                if processed % Self.progressStride == 0 || processed == total {
                    let done = processed
                    DispatchQueue.main.async { progress(done, total) }
                }
            }

            // 5. 距离升序（= 相似度降序）取 Top N；基准排除二次校验（强制规则兜底）
            let results = Array(scored
                .sorted { $0.distance < $1.distance }
                .prefix(max(0, topN))
                .map(\.asset)
                // 【强制】结果兜底：无论如何不允许基准自身出现
                .filter { $0.localIdentifier != baseID })

            // 刷新快照备忘：下次进入该照片的详情页时同步直出本次结果
            storeLock.lock()
            snapshotMemo[baseID] = results
            storeLock.unlock()

            self.finish(results, nil, token: token, completion)
        }
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
            workQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                guard let basePrint = self.cachedObservation(for: base) else {
                    continuation.resume(returning: nil)
                    return
                }

                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(
                    format: "mediaType == %d", PHAssetMediaType.image.rawValue
                )
                let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
                let baseID = base.localIdentifier

                var scored: [(asset: PHAsset, distance: Float)] = []
                fetchResult.enumerateObjects { asset, _, _ in
                    guard asset.localIdentifier != baseID else { return }
                    guard let print = self.cachedObservation(for: asset) else { return }
                    var distance: Float = .greatestFiniteMagnitude
                    if (try? basePrint.computeDistance(&distance, to: print)) != nil,
                       distance <= maxDistance {
                        scored.append((asset, distance))
                    }
                }

                let results = Array(scored
                    .sorted { $0.distance < $1.distance }
                    .prefix(max(0, topN))
                    .map(\.asset)
                    .filter { $0.localIdentifier != baseID })
                self.storeLock.lock()
                self.snapshotMemo[baseID] = results
                self.storeLock.unlock()
                continuation.resume(returning: results)
            }
        }
    }

    /// 取消进行中的检索（如详情页已切换到其他照片）：
    /// 在跑任务会尽快以 `.cancelled` 错误回调，后续新检索立即获得队列
    func cancel() {
        workQueue.async { [weak self] in
            self?.activeToken = nil
        }
    }

    // MARK: - Private

    /// 统一完成出口：每次调用保证回调一次。
    /// 「正常完成但令牌已被取代」时静默丢弃（新检索已接管结果语义），
    /// 「取消/失败」路径始终回调，让调用方能清理 loading 态
    private func finish(
        _ results: [PHAsset],
        _ error: Error?,
        token: UUID,
        _ completion: @escaping ([PHAsset], Error?) -> Void
    ) {
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

    /// 会话特征库查询：素材被编辑过（modificationDate 变化）视为失效
    private func cachedObservation(for asset: PHAsset) -> VNFeaturePrintObservation? {
        ensureFeatureStoreLoaded()
        storeLock.lock()
        defer { storeLock.unlock() }
        guard let feature = featureStore?[asset.localIdentifier],
              feature.modificationDate == asset.modificationDate else {
            return nil
        }
        return feature.observation
    }

    /// 写入会话特征库并持久化到磁盘（写通：扫描中断不丢已完成部分）
    private func remember(_ observation: VNFeaturePrintObservation, for asset: PHAsset) {
        ensureFeatureStoreLoaded()
        storeLock.lock()
        featureStore?[asset.localIdentifier] = CachedFeature(
            observation: observation,
            modificationDate: asset.modificationDate
        )
        storeLock.unlock()
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
        workQueue.async { [weak self] in
            self?.ensureFeatureStoreLoaded()
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
            request.usesCPUOnly = true
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

    /// 同步读取本地缩略图（禁网）：有则返回（可能是降级图，特征提取足够用），
    /// 本地完全无图时返回 nil
    private func localThumbnail(of asset: PHAsset, maxPixel: CGFloat) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false
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
        }
        return results
    }

    /// 写入/更新缓存（写通：每次即存，扫描中断也不丢已完成部分）。
    /// 序列化走 NSSecureCoding 归档（VNFeaturePrintObservation 遵循）
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
            try? self.context.save()
        }
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
