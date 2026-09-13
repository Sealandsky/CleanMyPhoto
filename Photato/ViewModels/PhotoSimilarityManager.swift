import Foundation
import Photos
import UIKit
import CoreData
import Observation

// MARK: - Core Data Object

@objc(PhotoFingerprint)
public class PhotoFingerprint: NSManagedObject {
    @NSManaged public var localIdentifier: String
    @NSManaged public var dhash: String
    @NSManaged public var creationDate: Date?
    @NSManaged public var pixelWidth: Int32
    @NSManaged public var pixelHeight: Int32
    @NSManaged public var computedAt: Date
    @NSManaged public var fileSize: Int64

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoFingerprint> {
        return NSFetchRequest<PhotoFingerprint>(entityName: "PhotoFingerprint")
    }
}

// MARK: - PhotoSimilarityManager

@MainActor
@Observable
final class PhotoSimilarityManager {

    var isComputing = false
    var computingProgress: Double = 0
    var currentStep = ""
    @ObservationIgnored private var _persistentContainer: NSPersistentContainer?
    private static let currentEngineVersion = 7
    private static let engineVersionKey = "PhotoSimilarityManager.engineVersion"

    init() {
        checkEngineVersion()
    }

    private func checkEngineVersion() {
        let savedVersion = UserDefaults.standard.integer(forKey: Self.engineVersionKey)
        if savedVersion < Self.currentEngineVersion {
            clearCache()
            UserDefaults.standard.set(Self.currentEngineVersion, forKey: Self.engineVersionKey)
        }
    }

    @ObservationIgnored
    private var persistentContainer: NSPersistentContainer {
        if let container = _persistentContainer { return container }
        let container = NSPersistentContainer(
            name: "PhotoSimilarity",
            managedObjectModel: Self.managedObjectModel
        )

        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        let storeURL = appSupportURL.appendingPathComponent("PhotoSimilarity.sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error = error {
                print("Core Data load error: \(error)")
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
        let request = PhotoFingerprint.fetchRequest()
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    // MARK: - Core Data Model (programmatic)

    private static let managedObjectModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "PhotoFingerprint"
        entity.managedObjectClassName = "PhotoFingerprint"

        let localId = NSAttributeDescription()
        localId.name = "localIdentifier"
        localId.attributeType = .stringAttributeType
        localId.isOptional = false

        let dhashAttr = NSAttributeDescription()
        dhashAttr.name = "dhash"
        dhashAttr.attributeType = .stringAttributeType
        dhashAttr.isOptional = false

        let creationDate = NSAttributeDescription()
        creationDate.name = "creationDate"
        creationDate.attributeType = .dateAttributeType
        creationDate.isOptional = true

        let width = NSAttributeDescription()
        width.name = "pixelWidth"
        width.attributeType = .integer32AttributeType
        width.isOptional = false
        width.defaultValue = 0

        let height = NSAttributeDescription()
        height.name = "pixelHeight"
        height.attributeType = .integer32AttributeType
        height.isOptional = false
        height.defaultValue = 0

        let computedAt = NSAttributeDescription()
        computedAt.name = "computedAt"
        computedAt.attributeType = .dateAttributeType
        computedAt.isOptional = false

        let fileSizeAttr = NSAttributeDescription()
        fileSizeAttr.name = "fileSize"
        fileSizeAttr.attributeType = .integer64AttributeType
        fileSizeAttr.isOptional = false
        fileSizeAttr.defaultValue = 0

        entity.properties = [localId, dhashAttr, creationDate, width, height, computedAt, fileSizeAttr]

        model.entities = [entity]
        return model
    }()

    // MARK: - Incremental Hash Computation

    func computeIfNeeded(assets fetchResult: PHFetchResult<PHAsset>) async {
        let cachedIds = loadCachedIdentifiers()

        var newAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image else { return }
            if !cachedIds.contains(asset.localIdentifier) {
                newAssets.append(asset)
            }
        }

        guard !newAssets.isEmpty else { return }

        isComputing = true
        computingProgress = 0
        currentStep = String(localized: "Computing fingerprints...")

        let batchSize = 100
        let total = newAssets.count

        for batchStart in stride(from: 0, to: total, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, total)
            let batch = Array(newAssets[batchStart..<batchEnd])

            computingProgress = Double(batchEnd) / Double(total)
            currentStep = String(localized: "Computing photo \(batchEnd)/\(total)...")

            let fingerprints = await withCheckedContinuation { (continuation: CheckedContinuation<[FingerprintData], Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    var results: [FingerprintData] = []
                    for asset in batch {
                        let hash = Self.computeDHash(for: asset)
                        results.append(FingerprintData(
                            localIdentifier: asset.localIdentifier,
                            dhash: hash,
                            dhashBits: Self.parseDHashBits(hash),
                            creationDate: asset.creationDate,
                            pixelWidth: Int32(asset.pixelWidth),
                            pixelHeight: Int32(asset.pixelHeight),
                            fileSize: 0
                        ))
                    }
                    continuation.resume(returning: results)
                }
            }

            saveFingerprints(fingerprints)
        }

        isComputing = false
        currentStep = ""
    }

    // MARK: - Similar & Duplicate Groups

    func similarAndDuplicateGroups(skipValidation: Bool = false) async -> (similar: [OrganizeScanGroup], duplicates: [OrganizeScanGroup]) {
        let fingerprints = loadAllFingerprints()
        guard fingerprints.count > 1 else { return ([], []) }

        let validFingerprints = skipValidation ? fingerprints : validateAndClean(fingerprints)
        guard validFingerprints.count > 1 else { return ([], []) }

        return await Task.detached(priority: .userInitiated) {
            let similar = Self.computeSimilarGroups(from: validFingerprints)
            let duplicates = Self.computeDuplicateGroups(from: validFingerprints)
            return (similar, duplicates)
        }.value
    }

    // MARK: - Private: Group Computation

    nonisolated private static func computeSimilarGroups(from fingerprints: [FingerprintData]) -> [OrganizeScanGroup] {
        // 过滤无指纹、无拍摄时间或无有效尺寸的脏数据，并按拍摄时间升序排布
        let sorted = fingerprints
            .filter {
                $0.dhashBits != 0 &&
                $0.creationDate != nil &&
                $0.pixelWidth > 0 &&
                $0.pixelHeight > 0
            }
            .sorted { ($0.creationDate!) < ($1.creationDate!) }

        guard sorted.count > 1 else { return [] }

        var usedIndices = Set<Int>()
        var clusterGroups: [(ids: [String], sampleDate: Date)] = []

        // 锚点贪心聚类 + 多维硬约束（宽高比、分辨率比例、单簇最大时间跨度、整簇直径硬约束）
        for i in 0..<sorted.count {
            if usedIndices.contains(i) { continue }

            let anchor = sorted[i]
            let anchorDate = anchor.creationDate!
            let anchorAspectRatio = Double(anchor.pixelWidth) / Double(anchor.pixelHeight)
            let anchorPixels = Double(anchor.pixelWidth * anchor.pixelHeight)

            var clusterMembers = [anchor]
            var clusterIndices = [i]

            for j in (i + 1)..<sorted.count {
                if usedIndices.contains(j) { continue }

                let candidate = sorted[j]
                let candDate = candidate.creationDate!
                let dtAnchor = candDate.timeIntervalSince(anchorDate)

                // 跨场景阻断：单簇时间跨度严格限制在 60 秒内（连拍或同场景拍摄）
                guard dtAnchor >= 0 else { continue }
                guard dtAnchor <= 60 else { break }

                let lastDate = clusterMembers.last!.creationDate!
                let dtLast = candDate.timeIntervalSince(lastDate)
                // 相邻照片时间间隔超过 20 秒，视为动作中断，终止向后串联
                guard dtLast <= 20 else { break }

                // 1. 宽高比硬约束：差异必须 < 0.15（彻底剔除长截屏与相机 4:3 混杂、横图与竖图混杂）
                let candAspectRatio = Double(candidate.pixelWidth) / Double(candidate.pixelHeight)
                guard abs(anchorAspectRatio - candAspectRatio) < 0.15 else { continue }

                // 2. 分辨率比例硬约束：像素总量倍数必须 < 1.5（剔除缩略图/预览图与全高清大图混杂）
                let candPixels = Double(candidate.pixelWidth * candidate.pixelHeight)
                let pixelRatio = max(anchorPixels, candPixels) / max(1.0, min(anchorPixels, candPixels))
                guard pixelRatio < 1.5 else { continue }

                // 3. 分级严格汉明距离阈值：
                // 超短时抓拍 (<=3s) 允许差异 <= 6；同场景连续拍摄 (<=15s) <= 5；微调构图 (<=60s) <= 3
                let tau: Int
                if dtLast <= 3 || dtAnchor <= 3 {
                    tau = 6
                } else if dtLast <= 15 || dtAnchor <= 15 {
                    tau = 5
                } else {
                    tau = 3
                }

                let distToAnchor = Self.hammingDistance(candidate.dhashBits, anchor.dhashBits)
                guard distToAnchor <= tau else { continue }

                // 4. 簇直径硬约束：新照片与簇内所有已有照片的最大汉明距离必须 <= 6，彻底杜绝长链漂移
                var isConsistentWithAll = true
                for member in clusterMembers {
                    if Self.hammingDistance(candidate.dhashBits, member.dhashBits) > 6 {
                        isConsistentWithAll = false
                        break
                    }
                }

                if isConsistentWithAll {
                    clusterMembers.append(candidate)
                    clusterIndices.append(j)
                    // 单簇上限 30 张，防止异常暴增
                    if clusterMembers.count >= 30 {
                        break
                    }
                }
            }

            if clusterMembers.count >= 2 {
                let ids = clusterMembers.map(\.localIdentifier)
                let latestDate = clusterMembers.compactMap(\.creationDate).max() ?? anchorDate
                clusterGroups.append((ids: ids, sampleDate: latestDate))
                usedIndices.formUnion(clusterIndices)
            }
        }

        // 按最新拍摄时间倒序排列分组（时间最新在前），确保首屏加载即为最新分组
        return clusterGroups
            .sorted { $0.sampleDate > $1.sampleDate }
            .map { cluster in
                OrganizeScanGroup(
                    category: .similar,
                    title: String(localized: "\(cluster.ids.count) similar"),
                    localIdentifiers: cluster.ids,
                    sampleDate: cluster.sampleDate
                )
            }
    }

    nonisolated private static func computeDuplicateGroups(from fingerprints: [FingerprintData]) -> [OrganizeScanGroup] {
        var groups: [String: [FingerprintData]] = [:]
        for fp in fingerprints {
            guard fp.dhashBits != 0 else {
                // 指纹为 0 时（如纯黑/白图）仅同日两秒内归并，防止跨月纯色图误伤
                let dateKey = fp.creationDate.map { "\(Int($0.timeIntervalSince1970 / 2) * 2)" } ?? "none"
                let key = "zero_\(fp.pixelWidth)x\(fp.pixelHeight)_\(dateKey)"
                groups[key, default: []].append(fp)
                continue
            }
            // 真实有效指纹且尺寸完全一致：判定为确定性重复照片（支持跨时间保存的相同文件）
            let key = "\(fp.dhashBits)_\(fp.pixelWidth)x\(fp.pixelHeight)"
            groups[key, default: []].append(fp)
        }

        let validGroups = groups.values.filter { $0.count > 1 }
        // 按最新拍摄时间倒序排列（最新在前）
        let sorted = validGroups.sorted { group1, group2 in
            let date1 = group1.compactMap(\.creationDate).max() ?? .distantPast
            let date2 = group2.compactMap(\.creationDate).max() ?? .distantPast
            return date1 > date2
        }

        return sorted.map { members in
            let ids = members.map(\.localIdentifier)
            let latestDate = members.compactMap(\.creationDate).max()
            return OrganizeScanGroup(
                category: .duplicates,
                title: String(localized: "\(ids.count) duplicates"),
                localIdentifiers: ids,
                sampleDate: latestDate
            )
        }
    }

    // MARK: - File Size Cache

    func getOrFetchFileSize(for asset: PHAsset) async -> Int64 {
        let request = PhotoFingerprint.fetchRequest()
        request.predicate = NSPredicate(format: "localIdentifier == %@", asset.localIdentifier)
        request.fetchLimit = 1

        if let fp = try? context.fetch(request).first, fp.fileSize > 0 {
            return fp.fileSize
        }

        let size = await PHAssetSizeHelper.getAssetSize(asset)
        if size > 0 {
            upsertFileSize(asset.localIdentifier, size: size,
                           creationDate: asset.creationDate,
                           pixelWidth: Int32(asset.pixelWidth),
                           pixelHeight: Int32(asset.pixelHeight))
        }
        return size
    }

    func largeFileGroup() -> OrganizeScanGroup? {
        let minSize: Int64 = 10 * 1024 * 1024
        let highResThreshold: Int32 = 6000 * 4000
        let highResMinSize: Int64 = 6 * 1024 * 1024

        let request = PhotoFingerprint.fetchRequest()
        request.predicate = NSPredicate(
            format: "fileSize >= %lld OR (pixelWidth * pixelHeight >= %d AND fileSize >= %lld)",
            minSize, highResThreshold, highResMinSize
        )

        let results = (try? context.fetch(request)) ?? []
        guard !results.isEmpty else { return nil }

        let sorted = results.sorted { $0.fileSize > $1.fileSize }
        let totalSize = sorted.reduce(Int64(0)) { $0 + $1.fileSize }

        return OrganizeScanGroup(
            category: .largeFiles,
            title: String(localized: "Large Files"),
            localIdentifiers: sorted.map { $0.localIdentifier },
            potentialSpaceSaved: totalSize
        )
    }

    func lowQualityGroup() -> OrganizeScanGroup? {
        let request = PhotoFingerprint.fetchRequest()
        request.predicate = NSPredicate(format: "pixelWidth * pixelHeight < %d AND fileSize <= %lld AND fileSize > 0",
                                        1920 * 1080, 50 * 1024)

        let results = (try? context.fetch(request)) ?? []
        guard !results.isEmpty else { return nil }

        let sorted = results.sorted { Int($0.pixelWidth) * Int($0.pixelHeight) < Int($1.pixelWidth) * Int($1.pixelHeight) }

        return OrganizeScanGroup(
            category: .lowQuality,
            title: String(localized: "Low Quality"),
            localIdentifiers: sorted.map { $0.localIdentifier }
        )
    }

    // MARK: - Cache Management

    func clearCache() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "PhotoFingerprint")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        _ = try? context.execute(deleteRequest)
        try? context.save()
    }

    // MARK: - Private: Core Data Helpers

    private struct FingerprintData: Sendable {
        let localIdentifier: String
        let dhash: String
        let dhashBits: UInt64
        let creationDate: Date?
        let pixelWidth: Int32
        let pixelHeight: Int32
        let fileSize: Int64
    }

    nonisolated static func parseDHashBits(_ dhash: String) -> UInt64 {
        if dhash.count == 64 {
            return UInt64(dhash, radix: 2) ?? 0
        } else if !dhash.isEmpty {
            return UInt64(dhash, radix: 16) ?? 0
        }
        return 0
    }

    private func loadCachedIdentifiers() -> Set<String> {
        let request = PhotoFingerprint.fetchRequest()
        request.predicate = NSPredicate(format: "dhash != nil AND dhash != ''")
        request.propertiesToFetch = ["localIdentifier"]

        let results = (try? context.fetch(request)) ?? []
        return Set(results.map { $0.localIdentifier })
    }

    private func saveFingerprints(_ data: [FingerprintData]) {
        guard !data.isEmpty else { return }
        let ids = data.map(\.localIdentifier)
        let request = PhotoFingerprint.fetchRequest()
        request.predicate = NSPredicate(format: "localIdentifier IN %@", ids)
        let existingFPs = (try? context.fetch(request)) ?? []
        let existingMap = Dictionary(existingFPs.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        for item in data {
            guard !item.dhash.isEmpty else { continue }
            let fp = existingMap[item.localIdentifier] ?? PhotoFingerprint(context: context)
            fp.localIdentifier = item.localIdentifier
            fp.dhash = item.dhash
            fp.creationDate = item.creationDate
            fp.pixelWidth = item.pixelWidth
            fp.pixelHeight = item.pixelHeight
            if item.fileSize > 0 {
                fp.fileSize = item.fileSize
            }
            fp.computedAt = Date()
        }
        try? context.save()
    }

    private func upsertFileSize(_ identifier: String, size: Int64,
                                 creationDate: Date?, pixelWidth: Int32, pixelHeight: Int32) {
        let request = PhotoFingerprint.fetchRequest()
        request.predicate = NSPredicate(format: "localIdentifier == %@", identifier)
        request.fetchLimit = 1

        if let fp = try? context.fetch(request).first {
            fp.fileSize = size
        } else {
            let fp = PhotoFingerprint(context: context)
            fp.localIdentifier = identifier
            fp.dhash = ""
            fp.creationDate = creationDate
            fp.pixelWidth = pixelWidth
            fp.pixelHeight = pixelHeight
            fp.fileSize = size
            fp.computedAt = Date()
        }
        try? context.save()
    }

    private func loadAllFingerprints() -> [FingerprintData] {
        let request = PhotoFingerprint.fetchRequest()
        request.predicate = NSPredicate(format: "dhash != nil AND dhash != ''")
        request.fetchBatchSize = 500

        let results = (try? context.fetch(request)) ?? []
        var unique: [String: FingerprintData] = [:]
        for fp in results {
            guard !fp.dhash.isEmpty else { continue }
            let bits = Self.parseDHashBits(fp.dhash)
            guard bits != 0 else { continue }
            unique[fp.localIdentifier] = FingerprintData(
                localIdentifier: fp.localIdentifier,
                dhash: fp.dhash,
                dhashBits: bits,
                creationDate: fp.creationDate,
                pixelWidth: fp.pixelWidth,
                pixelHeight: fp.pixelHeight,
                fileSize: fp.fileSize
            )
        }
        return Array(unique.values)
    }

    private func validateAndClean(_ fingerprints: [FingerprintData]) -> [FingerprintData] {
        let identifiers = fingerprints.map { $0.localIdentifier }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)

        var validIds = Set<String>()
        fetchResult.enumerateObjects { asset, _, _ in
            validIds.insert(asset.localIdentifier)
        }

        let staleIds = Set(identifiers).subtracting(validIds)
        if !staleIds.isEmpty {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "PhotoFingerprint")
            request.predicate = NSPredicate(format: "localIdentifier IN %@", Array(staleIds))
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            _ = try? context.execute(deleteRequest)
        }

        return fingerprints.filter { validIds.contains($0.localIdentifier) }
    }

    // MARK: - dHash (Difference Hash)

    nonisolated private static func computeDHash(for asset: PHAsset) -> String {
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

            var minVal = 255
            var maxVal = 0
            for i in 0..<(width * height) {
                let v = Int(pixels[i])
                if v < minVal { minVal = v }
                if v > maxVal { maxVal = v }
            }
            // 过滤无动态对比度的图像（纯黑、深灰锁屏、纯白界面等），防止噪点产生伪指纹
            guard maxVal - minVal >= 12 else { return }

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

    // MARK: - Hamming Distance

    nonisolated private static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
