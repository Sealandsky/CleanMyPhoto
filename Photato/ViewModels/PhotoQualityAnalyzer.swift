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
    @NSManaged public var computedAt: Date

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoQuality> {
        return NSFetchRequest<PhotoQuality>(entityName: "PhotoQuality")
    }
}

// MARK: - PhotoQualityAnalyzer
//
// AI-based bad-photo detection, fully on-device (no upload, no server).
// Mirrors the architecture of PhotoSimilarityManager: programmatic Core Data
// model in its own store, incremental computation, batched background work.
//
// Two signals per photo:
//   - blurScore: Laplacian variance over a small grayscale thumbnail.
//       Industry-standard sharpness measure; lower variance = blurrier.
//   - faceQuality: Vision capture quality (0~1) for the worst face in frame.
//       Covers closed eyes, motion blur on faces, sideways faces. -1 = no face.
//
// Thresholds below are empirical starting values derived from 256-long-edge
// thumbnails. They live as constants so they can be tuned without recomputing
// scores — the fetch just re-filters by the new threshold.

@MainActor
@Observable
final class PhotoQualityAnalyzer {

    // Tunable thresholds (re-evaluate against a real library before shipping).
    // Marked nonisolated: plain constants read from background analysis code.
    nonisolated static let blurThreshold: Double = 80.0   // Laplacian variance < this => blurry
    nonisolated static let faceThreshold: Double = 0.3   // face capture quality < this => poor face
    nonisolated static let thumbnailDimension: Int = 256  // long edge of the thumbnail used for analysis

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
            if let error = error {
                print("PhotoQuality Core Data load error: \(error)")
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

        let computedAt = NSAttributeDescription()
        computedAt.name = "computedAt"
        computedAt.attributeType = .dateAttributeType
        computedAt.isOptional = false

        entity.properties = [localId, blurAttr, faceAttr, computedAt]

        model.entities = [entity]
        return model
    }()

    // MARK: - Incremental Analysis

    func computeIfNeeded(assets fetchResult: PHFetchResult<PHAsset>) async {
        let cachedIds = loadCachedIdentifiers()

        var newAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            // Skip screenshots: always sharp, never contain faces — quality
            // analysis is meaningless for them and they often dominate a library.
            guard asset.mediaType == .image,
                  !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            if !cachedIds.contains(asset.localIdentifier) {
                newAssets.append(asset)
            }
        }

        guard !newAssets.isEmpty else { return }

        isComputing = true
        computingProgress = 0
        currentStep = String(localized: "Analyzing photo quality...")

        let total = newAssets.count
        // Vision + image decode are CPU-bound, so going wider than the core
        // count just adds contention. Reserve one core for the UI.
        let maxConcurrency = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)

        // Process in batches: each batch runs its photos in parallel, then
        // flushes to Core Data in one transaction back on the main actor.
        let batchSize = 50

        for batchStart in stride(from: 0, to: total, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, total)
            let batch = Array(newAssets[batchStart..<batchEnd])

            let results = await withCheckedContinuation { (continuation: CheckedContinuation<[QualityData], Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let group = DispatchGroup()
                    let semaphore = DispatchSemaphore(value: maxConcurrency)
                    let lock = NSLock()
                    var output: [QualityData] = []
                    output.reserveCapacity(batch.count)
                    var doneInBatch = 0

                    for asset in batch {
                        semaphore.wait()
                        group.enter()
                        DispatchQueue.global(qos: .userInitiated).async {
                            let (blur, face) = Self.analyze(for: asset)

                            lock.lock()
                            output.append(QualityData(
                                localIdentifier: asset.localIdentifier,
                                blurScore: blur,
                                faceQuality: face
                            ))
                            doneInBatch += 1
                            let done = doneInBatch
                            lock.unlock()

                            // Per-photo progress (smooth), global count across the whole scan.
                            DispatchQueue.main.async {
                                self.computingProgress = Double(batchStart + done) / Double(total)
                                self.currentStep = String(localized: "Analyzing \(batchStart + done)/\(total)...")
                            }

                            semaphore.signal()
                            group.leave()
                        }
                    }

                    group.wait()
                    continuation.resume(returning: output)
                }
            }

            saveQuality(results)
        }

        isComputing = false
        currentStep = ""
    }

    // MARK: - Result Groups

    func blurryGroup() -> OrganizeScanGroup? {
        let request = PhotoQuality.fetchRequest()
        request.predicate = NSPredicate(format: "blurScore >= 0 AND blurScore < %f", Self.blurThreshold)

        let results = (try? context.fetch(request)) ?? []
        guard !results.isEmpty else { return nil }

        // Blurriest first.
        let sorted = results.sorted { $0.blurScore < $1.blurScore }

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

    private struct QualityData {
        let localIdentifier: String
        let blurScore: Double
        let faceQuality: Double
    }

    private func loadCachedIdentifiers() -> Set<String> {
        let request = PhotoQuality.fetchRequest()
        request.propertiesToFetch = ["localIdentifier"]

        let results = (try? context.fetch(request)) ?? []
        return Set(results.map { $0.localIdentifier })
    }

    private func saveQuality(_ data: [QualityData]) {
        for item in data {
            let q = PhotoQuality(context: context)
            q.localIdentifier = item.localIdentifier
            q.blurScore = item.blurScore
            q.faceQuality = item.faceQuality
            q.computedAt = Date()
        }
        try? context.save()
    }

    // MARK: - Analysis (background-safe)

    nonisolated private static func analyze(for asset: PHAsset) -> (blur: Double, face: Double) {
        guard let cgImage = requestThumbnail(for: asset) else {
            return (-1, -1)
        }
        let blur = laplacianVariance(cgImage)
        let face = faceCaptureQuality(cgImage)
        return (blur, face)
    }

    /// Requests a small thumbnail strictly from local storage (no iCloud upload).
    nonisolated private static func requestThumbnail(for asset: PHAsset) -> CGImage? {
        let options = PHImageRequestOptions()
        options.resizeMode = .fast
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true

        let dim = CGFloat(thumbnailDimension)
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
}
