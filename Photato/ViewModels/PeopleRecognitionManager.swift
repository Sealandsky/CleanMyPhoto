import SwiftUI
import Photos
import Vision
import Combine
import CoreML

// MARK: - People Recognition & Clustering Manager
/// 负责纯本地端侧人脸检测、特征向量提取与余弦距离聚类引擎。
/// 严格保证 100% 离线计算，零网络交互，符合 iOS 隐私规范。
@MainActor
final class PeopleRecognitionManager: ObservableObject {
    static let shared = PeopleRecognitionManager()

    @Published var people: [PersonEntity] = []
    @Published var isScanning: Bool = false
    @Published var hasScannedOnce: Bool = false
    @Published var progress: Double = 0.0

    /// 内存中保存各人物代表性特征指纹（用于毫秒级余弦聚类比较）
    private var clusterFeaturePrints: [String: VNFeaturePrintObservation] = [:]
    /// 已完成扫描的素材 ID 集合（增量扫描避免重复计算）
    private var processedAssetIDs: Set<String> = []

    /// 特征比对余弦距离阈值：≤ 0.42 判定为同一人物
    private let matchDistanceThreshold: Float = 0.42

    /// 后台计算专用串行队列
    private let scanQueue = DispatchQueue(label: "cn.bryan.photato.people.recognition", qos: .utility)
    private var isScanTaskRunning = false

    init() {
        loadCachedPeople()
    }

    // MARK: - Persistence (沙盒 people_index.json)

    private var storageURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Photato", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("people_index.json")
    }

    private var processedIDsURL: URL {
        storageURL.deletingLastPathComponent().appendingPathComponent("people_processed_ids.json")
    }

    /// 从本地缓存快速载入历史人物聚类索引（第 0 帧极速直出）
    func loadCachedPeople() {
        let url = storageURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            hasScannedOnce = false
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([PersonEntity].self, from: data)
            self.people = Self.sortPeople(decoded)
            self.hasScannedOnce = true

            // 载入各人物代表性特征
            for person in self.people {
                if let fpDataStr = person.featurePrintData,
                   let fpData = Data(base64Encoded: fpDataStr),
                   let fp = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: fpData) {
                    clusterFeaturePrints[person.id] = fp
                }
            }

            // 载入已处理 ID 集合
            if let idsData = try? Data(contentsOf: processedIDsURL),
               let ids = try? JSONDecoder().decode(Set<String>.self, from: idsData) {
                self.processedAssetIDs = ids
            }
        } catch {
            print("[PeopleRecognitionManager] Failed to load cache: \(error)")
        }
    }

    /// 持久化人物索引至沙盒
    func savePeople() {
        let list = self.people
        let ids = self.processedAssetIDs
        let url = self.storageURL
        let idsUrl = self.processedIDsURL

        scanQueue.async {
            do {
                let data = try JSONEncoder().encode(list)
                try data.write(to: url, options: .atomic)

                let idsData = try JSONEncoder().encode(ids)
                try idsData.write(to: idsUrl, options: .atomic)
            } catch {
                print("[PeopleRecognitionManager] Failed to save: \(error)")
            }
        }
    }

    private static func sortPeople(_ list: [PersonEntity]) -> [PersonEntity] {
        list.sorted { p1, p2 in
            if p1.isFavorite != p2.isFavorite {
                return p1.isFavorite && !p2.isFavorite
            }
            return p1.photoIDs.count > p2.photoIDs.count
        }
    }

    // MARK: - Scan & Cluster Pipeline

    /// 触发人脸识别与聚类流水线
    /// - Parameter force: 是否强制重新全量扫描
    func scanPhotoLibrary(force: Bool = false) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        print("[PeopleRecognitionManager] scanPhotoLibrary called, authStatus: \(status.rawValue), force: \(force)")
        guard status == .authorized || status == .limited else {
            print("[PeopleRecognitionManager] Photo access not authorized: \(status.rawValue)")
            return
        }

        guard !isScanTaskRunning else { return }
        isScanTaskRunning = true
        isScanning = true

        if force || people.isEmpty {
            processedAssetIDs.removeAll()
            clusterFeaturePrints.removeAll()
            people.removeAll()
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            await self.performBackgroundClustering()
        }
    }

    private func performBackgroundClustering() async {
        // 1. 获取所有图片素材（按创建时间倒序）
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        let totalCount = fetchResult.count
        print("[PeopleRecognitionManager] Starting scan, total image assets: \(totalCount)")

        guard totalCount > 0 else {
            await MainActor.run {
                self.isScanning = false
                self.hasScannedOnce = true
                self.isScanTaskRunning = false
            }
            return
        }

        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = false // 绝不访问网络，纯本地
        requestOptions.resizeMode = .fast

        var localPeople = await MainActor.run { self.people }
        var featureMap = await MainActor.run { self.clusterFeaturePrints }
        var processedSet = await MainActor.run { self.processedAssetIDs }

        let targetSize = CGSize(width: 480, height: 480)
        var analyzedBatchCount = 0

        // 2. 逐批次抽取与 Vision 分析
        for i in 0..<totalCount {
            let asset = fetchResult.object(at: i)
            let assetID = asset.localIdentifier

            if processedSet.contains(assetID) {
                continue
            }

            autoreleasepool {
                // 请求本地缩略图并标准化为朝上 (upright) 位图
                var assetCGImage: CGImage?
                imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: requestOptions
                ) { uiImage, _ in
                    guard let image = uiImage else { return }
                    if let cg = image.cgImage {
                        assetCGImage = cg
                    }
                }

                if let cgImage = assetCGImage {
                    let faces = self.detectFaces(in: cgImage)
                    for face in faces {
                        // 过滤过小的人脸（边界宽度或高度小于 0.08）
                        guard face.boundingBox.width >= 0.08, face.boundingBox.height >= 0.08 else { continue }

                        // 转换为 UIKit 坐标系归一化矩形 (origin at top-left)
                        let uiCropRect = CGRect(
                            x: face.boundingBox.origin.x,
                            y: 1.0 - face.boundingBox.origin.y - face.boundingBox.height,
                            width: face.boundingBox.width,
                            height: face.boundingBox.height
                        )

                        // 裁切人脸区域并提取特征指纹
                        if let faceCropCG = self.cropFace(cgImage: cgImage, boundingBox: face.boundingBox),
                           let featurePrint = self.extractFeaturePrint(from: faceCropCG) {

                            // 在已知聚类中搜寻最近匹配
                            var bestMatchID: String?
                            var minDistance: Float = Float.greatestFiniteMagnitude

                            for (clusterID, clusterFP) in featureMap {
                                var distance: Float = 0
                                if (try? featurePrint.computeDistance(&distance, to: clusterFP)) != nil {
                                    if distance < minDistance && distance <= self.matchDistanceThreshold {
                                        minDistance = distance
                                        bestMatchID = clusterID
                                    }
                                }
                            }

                            if let matchedID = bestMatchID,
                               let index = localPeople.firstIndex(where: { $0.id == matchedID }) {
                                // 匹配到现有聚类
                                if !localPeople[index].photoIDs.contains(assetID) {
                                    localPeople[index].photoIDs.append(assetID)
                                    localPeople[index].lastUpdated = Date()
                                }
                            } else {
                                // 未匹配到，新建聚类
                                let newID = UUID().uuidString
                                let fpData = try? NSKeyedArchiver.archivedData(withRootObject: featurePrint, requiringSecureCoding: true)
                                let newPerson = PersonEntity(
                                    id: newID,
                                    name: "",
                                    photoIDs: [assetID],
                                    avatarAssetID: assetID,
                                    faceCropRect: uiCropRect,
                                    isFavorite: false,
                                    lastUpdated: Date(),
                                    featurePrintData: fpData?.base64EncodedString()
                                )
                                localPeople.append(newPerson)
                                featureMap[newID] = featurePrint
                            }
                        }
                    }
                }
            }

            processedSet.insert(assetID)
            analyzedBatchCount += 1

            // 节流刷新到主线程：首批 5 张即更新，后续每 20 张更新一次，防止主线程卡顿
            if analyzedBatchCount == 5 || analyzedBatchCount % 20 == 0 || i == totalCount - 1 {
                let currentPeople = Self.sortPeople(localPeople)
                let currentFeatureMap = featureMap
                let currentProcessed = processedSet
                let currentProgress = Double(i + 1) / Double(totalCount)

                await MainActor.run {
                    self.people = currentPeople
                    self.clusterFeaturePrints = currentFeatureMap
                    self.processedAssetIDs = currentProcessed
                    self.progress = currentProgress
                    self.hasScannedOnce = true
                }
            }
        }

        // 3. 扫描结束完成持久化
        let finalPeople = Self.sortPeople(localPeople)
        let finalFeatureMap = featureMap
        let finalProcessed = processedSet
        NSLog("[PeopleRecognitionManager] Finished clustering. Total people: %ld", finalPeople.count)

        await MainActor.run {
            self.people = finalPeople
            self.clusterFeaturePrints = finalFeatureMap
            self.processedAssetIDs = finalProcessed
            self.isScanning = false
            self.hasScannedOnce = true
            self.isScanTaskRunning = false
            self.savePeople()
        }
    }

    // MARK: - Vision Helpers

    #if targetEnvironment(simulator)
    nonisolated private static func cpuComputeDevice() -> MLComputeDevice? {
        MLComputeDevice.allComputeDevices.first { device in
            if case .cpu = device { return true }
            return false
        }
    }
    #endif

    nonisolated private func detectFaces(in cgImage: CGImage) -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        #if targetEnvironment(simulator)
        if let cpuDevice = Self.cpuComputeDevice() {
            request.setComputeDevice(cpuDevice, for: .main)
        }
        #endif
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            return request.results ?? []
        } catch {
            NSLog("[PeopleRecognitionManager] detectFaces failed: %@", error.localizedDescription)
            return []
        }
    }

    nonisolated private func cropFace(cgImage: CGImage, boundingBox: CGRect) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Vision 坐标原点在左下角，转换为像素坐标
        // 适当外扩 15% 边距，包含人脸轮廓与发型边缘
        let marginX = boundingBox.width * 0.15
        let marginY = boundingBox.height * 0.15

        let expandedX = max(0, boundingBox.origin.x - marginX)
        let expandedY = max(0, boundingBox.origin.y - marginY)
        let expandedWidth = min(1.0 - expandedX, boundingBox.width + marginX * 2)
        let expandedHeight = min(1.0 - expandedY, boundingBox.height + marginY * 2)

        let pixelX = expandedX * width
        let pixelY = (1.0 - expandedY - expandedHeight) * height
        let pixelW = expandedWidth * width
        let pixelH = expandedHeight * height

        let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelW, height: pixelH).integral
        return cgImage.cropping(to: cropRect)
    }

    nonisolated private func extractFeaturePrint(from faceCGImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        #if targetEnvironment(simulator)
        if let cpuDevice = Self.cpuComputeDevice() {
            request.setComputeDevice(cpuDevice, for: .main)
        }
        #endif
        let handler = VNImageRequestHandler(cgImage: faceCGImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            NSLog("[PeopleRecognitionManager] extractFeaturePrint failed: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - User Operations

    /// 重命名人物
    func rename(_ person: PersonEntity, to newName: String) {
        guard let index = people.firstIndex(where: { $0.id == person.id }) else { return }
        people[index].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        people[index].lastUpdated = Date()
        savePeople()
    }

    /// 切换收藏状态（置顶）
    func toggleFavorite(_ person: PersonEntity) {
        guard let index = people.firstIndex(where: { $0.id == person.id }) else { return }
        people[index].isFavorite.toggle()
        people = Self.sortPeople(people)
        savePeople()
    }

    /// 从人物中剔除某张照片
    func removePhoto(id photoID: String, from person: PersonEntity) {
        guard let index = people.firstIndex(where: { $0.id == person.id }) else { return }
        people[index].photoIDs.removeAll(where: { $0 == photoID })
        if people[index].photoIDs.isEmpty {
            people.remove(at: index)
        } else if people[index].avatarAssetID == photoID {
            // 若封面被删除，替换为下一张照片
            people[index].avatarAssetID = people[index].photoIDs.first ?? ""
        }
        people = Self.sortPeople(people)
        savePeople()
    }
}
