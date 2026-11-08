import Foundation
import Photos
import UIKit
import CoreData
import Vision
import Observation

// MARK: - Core Data Object

@objc(PhotoQuality)
public class PhotoQuality: NSManagedObject {
    @NSManaged public var localIdentifier: String
    @NSManaged public var blurScore: Double      // Laplacian variance; lower = blurrier. -1 = unknown/uncomputed.
    @NSManaged public var faceQuality: Double     // VNFaceObservation.faceCaptureQuality 0~1; -1 = no face detected.
    @NSManaged public var aestheticsScore: Double // Vision aesthetics overallScore 0~1; -1 = not computed (only blur-band photos get it).
    @NSManaged public var isUtility: Bool         // Vision aesthetics utility flag (screenshot/receipt/document lookalikes).
    @NSManaged public var computedAt: Date

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoQuality> {
        return NSFetchRequest<PhotoQuality>(entityName: "PhotoQuality")
    }
}

// MARK: - Thread-Safe Batch Processing Helpers

private nonisolated struct QualityData: Sendable {
    let localIdentifier: String
    let blurScore: Double
    let faceQuality: Double
    let aestheticsScore: Double
    let isUtility: Bool
}

/// 一条待分析任务:全量分析(库中无行)或回填(已有行,仅模糊带照片补 aesthetics)
nonisolated private struct QualityWorkItem: Sendable {
    let asset: PHAsset
    let cachedBlur: Double
    let cachedFace: Double
    let isBackfill: Bool
}

// MARK: - PhotoQualityAnalyzer
//
// AI-based bad-photo detection, fully on-device (no upload, no server).
// Mirrors the architecture of PhotoSimilarityManager: programmatic Core Data
// model in its own store, incremental computation, batched background work.
//
// Signals per photo:
//   - blurScore: Laplacian variance over a small grayscale thumbnail.
//       Industry-standard sharpness measure; lower variance = blurrier.
//   - faceQuality: Vision capture quality (0~1) for the worst face in frame.
//       Covers motion blur on faces, sideways faces. -1 = no face.
//   - aestheticsScore: Vision aesthetics overallScore (0~1), computed only for
//       photos inside the Laplacian ambiguity band, where raw variance cannot
//       separate intentional bokeh / clean backgrounds from real blur. -1 =
//       not applicable.
//   - isUtility: aesthetics utility flag (screenshots, receipts, documents);
//       such photos are excluded from the blurry group.
//
// Thresholds below are empirical starting values derived from 256-long-edge
// thumbnails. They live as constants so they can be tuned without recomputing
// scores — the fetch just re-filters by the new threshold.

@MainActor
@Observable
final class PhotoQualityAnalyzer {

    // Tunable thresholds (re-evaluate against a real library before shipping).
    // Marked nonisolated: plain constants read from background analysis code.
    nonisolated static let blurBandLow: Double = 40.0     // Laplacian variance < this => definitely blurry, skip aesthetics
    nonisolated static let blurBandHigh: Double = 200.0   // Laplacian variance > this => definitely sharp, skip aesthetics
    nonisolated static let aestheticsThreshold: Double = 0.3  // in-band aesthetics overallScore < this => blurry
    nonisolated static let faceThreshold: Double = 0.3   // face capture quality < this => poor face
    nonisolated static let thumbnailDimension: Int = 256  // long edge of the thumbnail used for Laplacian + face analysis
    nonisolated static let aestheticsDimension: Int = 768 // long edge of the thumbnail used for aesthetics analysis

    var isComputing = false
    var computingProgress: Double = 0
    var currentStep = ""

    @ObservationIgnored private var _persistentContainer: NSPersistentContainer?

    @ObservationIgnored
    private var persistentContainer: NSPersistentContainer {
        if let container = _persistentContainer { return container }
        let container = NSPersistentContainer(
            name: "PhotoQuality",
            managedObjectModel: Self.managedObjectModel
        )

        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        let storeURL = appSupportURL.appendingPathComponent("PhotoQuality.sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            guard let error else { return }
            // 纯缓存库:模型迁移失败直接销毁重建,代价只是下次全量扫描重算
            print("PhotoQuality Core Data load error: \(error)")
            try? container.persistentStoreCoordinator.destroyPersistentStore(
                at: storeURL, ofType: NSSQLiteStoreType, options: nil
            )
            container.loadPersistentStores { _, retryError in
                if let retryError {
                    print("PhotoQuality Core Data reload error: \(retryError)")
                }
            }
        }
        _persistentContainer = container
        return container
    }

    @ObservationIgnored
    private var context: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    var hasCachedData: Bool {
        let request = PhotoQuality.fetchRequest()
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    // MARK: - Core Data Model (programmatic)

    private static let managedObjectModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "PhotoQuality"
        entity.managedObjectClassName = "PhotoQuality"

        let localId = NSAttributeDescription()
        localId.name = "localIdentifier"
        localId.attributeType = .stringAttributeType
        localId.isOptional = false

        let blurAttr = NSAttributeDescription()
        blurAttr.name = "blurScore"
        blurAttr.attributeType = .doubleAttributeType
        blurAttr.isOptional = false
        blurAttr.defaultValue = -1.0

        let faceAttr = NSAttributeDescription()
        faceAttr.name = "faceQuality"
        faceAttr.attributeType = .doubleAttributeType
        faceAttr.isOptional = false
        faceAttr.defaultValue = -1.0

        let aestheticsAttr = NSAttributeDescription()
        aestheticsAttr.name = "aestheticsScore"
        aestheticsAttr.attributeType = .doubleAttributeType
        aestheticsAttr.isOptional = false
        aestheticsAttr.defaultValue = -1.0

        let utilityAttr = NSAttributeDescription()
        utilityAttr.name = "isUtility"
        utilityAttr.attributeType = .booleanAttributeType
        utilityAttr.isOptional = false
        utilityAttr.defaultValue = false

        let computedAt = NSAttributeDescription()
        computedAt.name = "computedAt"
        computedAt.attributeType = .dateAttributeType
        computedAt.isOptional = false

        entity.properties = [localId, blurAttr, faceAttr, aestheticsAttr, utilityAttr, computedAt]

        model.entities = [entity]
        return model
    }()

    // MARK: - Incremental Analysis

    func computeIfNeeded(assets fetchResult: PHFetchResult<PHAsset>) async {
        let cached = loadCachedState()

        var workItems: [QualityWorkItem] = []
        fetchResult.enumerateObjects { asset, _, _ in
            // Skip screenshots: always sharp, never contain faces — quality
            // analysis is meaningless for them and they often dominate a library.
            guard asset.mediaType == .image,
                  !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            if let row = cached.scores[asset.localIdentifier] {
                // 已有缓存:仅模糊带内、aesthetics 尚未算成的照片需要回填;
                // 带外照片无需 aesthetics,行在即视为完成
                if row.aestheticsScore < 0,
                   row.blurScore >= Self.blurBandLow,
                   row.blurScore <= Self.blurBandHigh {
                    workItems.append(QualityWorkItem(
                        asset: asset,
                        cachedBlur: row.blurScore,
                        cachedFace: row.faceQuality,
                        isBackfill: true
                    ))
                }
            } else {
                workItems.append(QualityWorkItem(
                    asset: asset, cachedBlur: -1, cachedFace: -1, isBackfill: false
                ))
            }
        }

        guard !workItems.isEmpty else { return }

        isComputing = true
        computingProgress = 0
        currentStep = String(localized: "Analyzing photo quality...")

        let total = workItems.count
        // Vision + image decode are CPU-bound, so going wider than the core
        // count just adds contention. Reserve one core for the UI.
        let maxConcurrency = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)

        // Process in batches: each batch runs its photos in parallel, then
        // flushes to Core Data in one transaction back on the main actor.
        let batchSize = 50
        var allResults: [QualityData] = []
        allResults.reserveCapacity(total)

        for batchStart in stride(from: 0, to: total, by: batchSize) {
            // 用户取消分析或切入后台后立即停止后续批次，已完成批次已落盘可复用
            if Task.isCancelled { break }
            let batchEnd = min(batchStart + batchSize, total)
            let batch = Array(workItems[batchStart..<batchEnd])

            var batchResults: [QualityData] = []
            batchResults.reserveCapacity(batch.count)

            await withTaskGroup(of: QualityData.self) { group in
                var iterator = batch.makeIterator()

                // 启动初始并发任务（受 maxConcurrency 控制，避免抢占过多线程和 ANE 算力）
                for _ in 0..<maxConcurrency {
                    if let item = iterator.next() {
                        group.addTask {
                            await PhotoQualityAnalyzer.analyze(item: item)
                        }
                    }
                }

                // 每完成一个任务，存入结果并派发下一个，同时节流刷新 UI 进度
                while let result = await group.next() {
                    batchResults.append(result)

                    let currentTotal = batchStart + batchResults.count
                    let shouldUpdate = (currentTotal % 10 == 0) || (currentTotal == total) || (batchResults.count == batch.count)
                    if shouldUpdate {
                        self.computingProgress = Double(currentTotal) / Double(total)
                        self.currentStep = String(localized: "Analyzing \(currentTotal)/\(total)...")
                    }

                    if !Task.isCancelled, let nextItem = iterator.next() {
                        group.addTask {
                            await PhotoQualityAnalyzer.analyze(item: nextItem)
                        }
                    }
                }
            }

            guard !Task.isCancelled else { break }
            saveQuality(batchResults, existing: cached.objects)
            allResults.append(contentsOf: batchResults)
        }

        #if DEBUG
        Self.logDistribution(allResults)
        #endif

        isComputing = false
        currentStep = ""
    }

    // MARK: - Result Groups

    func blurryGroup() -> OrganizeScanGroup? {
        let request = PhotoQuality.fetchRequest()
        // 进组两类:方差硬糊(带下界以下);带内被 aesthetics 判糊且非功能图
        // (utility 命中的截图/单据/文档不按美学打分,留给后续独立分组)
        request.predicate = NSPredicate(
            format: "blurScore >= 0 AND (blurScore < %f OR (aestheticsScore >= 0 AND aestheticsScore < %f AND isUtility == NO))",
            Self.blurBandLow, Self.aestheticsThreshold
        )

        let results = (try? context.fetch(request)) ?? []
        guard !results.isEmpty else { return nil }

        // Worst first: aesthetics 分数优先(0~1),缺失时用归一化方差兜底
        func rank(_ q: PhotoQuality) -> Double {
            q.aestheticsScore >= 0 ? q.aestheticsScore : min(q.blurScore / Self.blurBandHigh, 1.0)
        }
        let sorted = results.sorted { rank($0) < rank($1) }

        return OrganizeScanGroup(
            category: .blurry,
            title: String(localized: "Blurry"),
            localIdentifiers: sorted.map { $0.localIdentifier }
        )
    }

    func poorFaceGroup() -> OrganizeScanGroup? {
        let request = PhotoQuality.fetchRequest()
        request.predicate = NSPredicate(format: "faceQuality >= 0 AND faceQuality < %f", Self.faceThreshold)

        let results = (try? context.fetch(request)) ?? []
        guard !results.isEmpty else { return nil }

        // Worst face first.
        let sorted = results.sorted { $0.faceQuality < $1.faceQuality }

        return OrganizeScanGroup(
            category: .poorFace,
            title: String(localized: "Blurry Faces"),
            localIdentifiers: sorted.map { $0.localIdentifier }
        )
    }

    // MARK: - Cache Management

    func clearCache() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "PhotoQuality")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        _ = try? context.execute(deleteRequest)
        try? context.save()
    }

    // MARK: - Private: Core Data Helpers

    private struct CachedRow {
        let blurScore: Double
        let faceQuality: Double
        let aestheticsScore: Double
    }

    /// 一次取全量缓存行:scores 用于跳过/回填判定,objects 用于回填时就地更新,
    /// 避免逐行 fetch 在大库上的 O(n²) 往返
    private func loadCachedState() -> (scores: [String: CachedRow], objects: [String: PhotoQuality]) {
        let request = PhotoQuality.fetchRequest()
        let results = (try? context.fetch(request)) ?? []

        var scores: [String: CachedRow] = [:]
        scores.reserveCapacity(results.count)
        var objects: [String: PhotoQuality] = [:]
        objects.reserveCapacity(results.count)
        for row in results {
            scores[row.localIdentifier] = CachedRow(
                blurScore: row.blurScore,
                faceQuality: row.faceQuality,
                aestheticsScore: row.aestheticsScore
            )
            objects[row.localIdentifier] = row
        }
        return (scores, objects)
    }

    private func saveQuality(_ data: [QualityData], existing: [String: PhotoQuality]) {
        guard !data.isEmpty else { return }
        for item in data {
            // 回填任务复用已有行,全量任务新建
            let q = existing[item.localIdentifier] ?? PhotoQuality(context: context)
            q.localIdentifier = item.localIdentifier
            q.blurScore = item.blurScore
            q.faceQuality = item.faceQuality
            q.aestheticsScore = item.aestheticsScore
            q.isUtility = item.isUtility
            q.computedAt = Date()
        }
        try? context.save()
    }

    // MARK: - Analysis (background-safe)

    nonisolated private static func analyze(item: QualityWorkItem) async -> QualityData {
        let id = item.asset.localIdentifier

        if Task.isCancelled {
            return QualityData(
                localIdentifier: id, blurScore: -1, faceQuality: -1,
                aestheticsScore: -1, isUtility: false
            )
        }

        // 回填:模糊带照片只补 aesthetics,已落库的 Laplacian / face 直接沿用
        if item.isBackfill {
            let (aesthetics, isUtility) = await aestheticsAnalysis(for: item.asset)
            return QualityData(
                localIdentifier: id,
                blurScore: item.cachedBlur,
                faceQuality: item.cachedFace,
                aestheticsScore: aesthetics,
                isUtility: isUtility
            )
        }

        guard let cgImage = requestThumbnail(for: item.asset, dimension: thumbnailDimension) else {
            return QualityData(
                localIdentifier: id, blurScore: -1, faceQuality: -1,
                aestheticsScore: -1, isUtility: false
            )
        }
        let blur = laplacianVariance(cgImage)
        let face = faceCaptureQuality(cgImage)

        // 两级流水线:方差落在模糊带,才值得花 768px 解码 + aesthetics 推理去
        // 分辨"真糊"与"景深虚化/干净背景";两端明确的直接定性
        var aesthetics: Double = -1
        var isUtility = false
        if blur >= blurBandLow, blur <= blurBandHigh, !Task.isCancelled {
            (aesthetics, isUtility) = await aestheticsAnalysis(for: item.asset)
        }

        return QualityData(
            localIdentifier: id,
            blurScore: blur,
            faceQuality: face,
            aestheticsScore: aesthetics,
            isUtility: isUtility
        )
    }

    /// Requests a small thumbnail strictly from local storage (no iCloud upload).
    nonisolated private static func requestThumbnail(for asset: PHAsset, dimension: Int) -> CGImage? {
        let options = PHImageRequestOptions()
        options.resizeMode = .fast
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true

        let dim = CGFloat(dimension)
        var result: CGImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: dim, height: dim),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            result = image?.cgImage
        }
        return result
    }

    /// Laplacian variance — standard image sharpness metric.
    /// Applies the kernel  0  1  0 / 1 -4 1 / 0 1 0  and returns the variance of
    /// the response. Low variance = few edges = blurry.
    nonisolated private static func laplacianVariance(_ cgImage: CGImage) -> Double {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 2, height > 2 else { return -1 }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return -1 }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = ctx.data else { return -1 }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

        var sum: Double = 0
        var sumSq: Double = 0
        var count: Int = 0

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let center = Double(pixels[idx])
                let up = Double(pixels[idx - width])
                let down = Double(pixels[idx + width])
                let left = Double(pixels[idx - 1])
                let right = Double(pixels[idx + 1])
                let lap = up + down + left + right - 4 * center
                sum += lap
                sumSq += lap * lap
                count += 1
            }
        }

        guard count > 0 else { return -1 }
        let mean = sum / Double(count)
        return sumSq / Double(count) - mean * mean
    }

    /// Worst (lowest) face capture quality among detected faces.
    /// Returns -1 when no face is found — such photos are never flagged as poor-face.
    nonisolated private static func faceCaptureQuality(_ cgImage: CGImage) -> Double {
        let request = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return -1
        }

        let observations = request.results ?? []
        guard !observations.isEmpty else { return -1 }

        // A group shot is only as good as its worst face.
        let qualities = observations.compactMap { $0.faceCaptureQuality }
        return Double(qualities.min() ?? -1)
    }

    /// Vision aesthetics (iOS 18+, new Swift API only — no legacy VN* class):
    /// overallScore 0~1 plus utility detection (photos of screenshots /
    /// receipts / documents). Runs on a larger thumbnail than the Laplacian
    /// pass because the score needs real detail. Returns -1 on failure — such
    /// photos simply keep their Laplacian verdict.
    nonisolated private static func aestheticsAnalysis(for asset: PHAsset) async -> (score: Double, isUtility: Bool) {
        guard !Task.isCancelled else { return (-1, false) }
        guard let cgImage = requestThumbnail(for: asset, dimension: aestheticsDimension) else {
            return (-1, false)
        }

        do {
            let observation = try await CalculateImageAestheticsScoresRequest().perform(on: cgImage)
            return (Double(observation.overallScore), observation.isUtility)
        } catch {
            return (-1, false)
        }
    }

    #if DEBUG
    /// 校准辅助:全量扫描结束后打印分数分布,按真机分位点定阈值用
    nonisolated private static func logDistribution(_ data: [QualityData]) {
        guard !data.isEmpty else { return }

        func percentiles(_ values: [Double], format: String) -> String {
            guard !values.isEmpty else { return "n/a" }
            let sorted = values.sorted()
            func p(_ q: Double) -> Double {
                let idx = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * q).rounded())))
                return sorted[idx]
            }
            return String(
                format: "p5=\(format) p25=\(format) p50=\(format) p75=\(format) p95=\(format)",
                p(0.05), p(0.25), p(0.5), p(0.75), p(0.95)
            )
        }

        let blurs = data.map(\.blurScore).filter { $0 >= 0 }
        let aesthetics = data.map(\.aestheticsScore).filter { $0 >= 0 }
        let bandCount = blurs.filter { $0 >= blurBandLow && $0 <= blurBandHigh }.count
        let utilityCount = data.filter(\.isUtility).count

        print("PhotoQuality distribution: n=\(data.count) "
            + "blur[\(percentiles(blurs, format: "%.0f"))] "
            + "band=\(bandCount)(\(Int(Double(bandCount) / Double(max(blurs.count, 1)) * 100))%) "
            + "aesthetics n=\(aesthetics.count) [\(percentiles(aesthetics, format: "%.3f"))] "
            + "utility=\(utilityCount)")
    }
    #endif
}
