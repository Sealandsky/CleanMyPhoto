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

    func similarAndDuplicateGroups(skipValidation: Bool = false) -> (similar: [OrganizeScanGroup], duplicates: [OrganizeScanGroup]) {
        let fingerprints = loadAllFingerprints()
        guard fingerprints.count > 1 else { return ([], []) }

        let validFingerprints = skipValidation ? fingerprints : validateAndClean(fingerprints)
        guard validFingerprints.count > 1 else { return ([], []) }

        return (computeSimilarGroups(from: validFingerprints), computeDuplicateGroups(from: validFingerprints))
    }

    // MARK: - Private: Group Computation

    private func computeSimilarGroups(from fingerprints: [FingerprintData]) -> [OrganizeScanGroup] {
        let sorted = fingerprints.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

        let uf = UnionFind()
        for fp in sorted { uf.add(fp.localIdentifier) }

        let threshold = 10
        let windowSeconds: TimeInterval = 3 * 86400

        for i in 0..<sorted.count {
            let fp = sorted[i]
            let date = fp.creationDate ?? .distantPast

            for j in (i + 1)..<sorted.count {
                let other = sorted[j]
                let otherDate = other.creationDate ?? .distantPast

                guard otherDate.timeIntervalSince(date) <= windowSeconds else { break }

                let dist = Self.hammingDistance(fp.dhash, other.dhash)
                if dist <= threshold {
                    uf.union(fp.localIdentifier, other.localIdentifier)
                }
            }
        }

        var groups: [String: [String]] = [:]
        for fp in sorted {
            let root = uf.find(fp.localIdentifier)
            groups[root, default: []].append(fp.localIdentifier)
        }

        return groups.values
            .filter { $0.count > 1 }
            .sorted { $0.count > $1.count }
            .map { ids in
                OrganizeScanGroup(
                    category: .similar,
                    title: String(localized: "\(ids.count) similar"),
                    localIdentifiers: ids
                )
            }
    }

    private func computeDuplicateGroups(from fingerprints: [FingerprintData]) -> [OrganizeScanGroup] {
        var groups: [String: [String]] = [:]
        for fp in fingerprints {
            let dateKey: String
            if let date = fp.creationDate {
                dateKey = "\(Int(date.timeIntervalSince1970 / 2) * 2)"
            } else {
                dateKey = "none"
            }
            let key = "\(fp.dhash)_\(dateKey)"
            groups[key, default: []].append(fp.localIdentifier)
        }

        return groups.values
            .filter { $0.count > 1 }
            .sorted { $0.count > $1.count }
            .map { ids in
                OrganizeScanGroup(
                    category: .duplicates,
                    title: String(localized: "\(ids.count) duplicates"),
                    localIdentifiers: ids
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
        let request = PhotoFingerprint.fetchRequest()
        request.predicate = NSPredicate(format: "pixelWidth * pixelHeight > %d AND fileSize > 0", 4000 * 4000)

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

    private struct FingerprintData {
        let localIdentifier: String
        let dhash: String
        let creationDate: Date?
        let pixelWidth: Int32
        let pixelHeight: Int32
        let fileSize: Int64
    }

    private func loadCachedIdentifiers() -> Set<String> {
        let request = PhotoFingerprint.fetchRequest()
        request.propertiesToFetch = ["localIdentifier"]

        let results = (try? context.fetch(request)) ?? []
        return Set(results.map { $0.localIdentifier })
    }

    private func saveFingerprints(_ data: [FingerprintData]) {
        for item in data {
            guard !item.dhash.isEmpty else { continue }
            let fp = PhotoFingerprint(context: context)
            fp.localIdentifier = item.localIdentifier
            fp.dhash = item.dhash
            fp.creationDate = item.creationDate
            fp.pixelWidth = item.pixelWidth
            fp.pixelHeight = item.pixelHeight
            fp.fileSize = item.fileSize
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
        request.fetchBatchSize = 500

        let results = (try? context.fetch(request)) ?? []
        return results.map { fp in
            FingerprintData(
                localIdentifier: fp.localIdentifier,
                dhash: fp.dhash,
                creationDate: fp.creationDate,
                pixelWidth: fp.pixelWidth,
                pixelHeight: fp.pixelHeight,
                fileSize: fp.fileSize
            )
        }
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
            targetSize: CGSize(width: 9, height: 8),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image = image, let cgImage = image.cgImage else { return }

            let width = 9
            let height = 8
            let colorSpace = CGColorSpaceCreateDeviceGray()
            guard let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

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

    // MARK: - Hamming Distance

    private static func hammingDistance(_ a: String, _ b: String) -> Int {
        guard a.count == b.count else { return Int.max }
        var distance = 0
        for (c1, c2) in zip(a, b) {
            if c1 != c2 { distance += 1 }
        }
        return distance
    }
}

// MARK: - Union-Find

private final class UnionFind {
    private var parent: [String: String] = [:]
    private var rank: [String: Int] = [:]

    func add(_ x: String) {
        if parent[x] == nil {
            parent[x] = x
            rank[x] = 0
        }
    }

    func find(_ x: String) -> String {
        if parent[x] != x {
            parent[x] = find(parent[x]!)
        }
        return parent[x]!
    }

    func union(_ x: String, _ y: String) {
        let rootX = find(x)
        let rootY = find(y)
        guard rootX != rootY else { return }

        if rank[rootX]! < rank[rootY]! {
            parent[rootX] = rootY
        } else if rank[rootX]! > rank[rootY]! {
            parent[rootY] = rootX
        } else {
            parent[rootY] = rootX
            rank[rootX]! += 1
        }
    }
}
