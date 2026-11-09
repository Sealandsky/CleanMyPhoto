import SwiftUI
import Combine

class StatisticsManager: ObservableObject {
    private let userDefaults = UserDefaults.standard

    // 持久化数据键
    private let totalDeletedPhotosKey = "totalDeletedPhotos"
    private let storageSpaceSavedBytesKey = "storageSpaceSavedBytes"
    private let lastPhotoCountKey = "lastPhotoCount"
    private let cleanupTimesKey = "cleanupTimes"

    // 持久化数据
    @Published private(set) var totalDeletedPhotos: Int = 0
    @Published private(set) var storageSpaceSavedBytes: Int = 0
    @Published private(set) var cleanupTimes: Int = 0

    // 实时数据（支持本地历史缓存快速呈现）
    @Published var currentPhotoCount: Int = 0
    @Published var videoCount: Int = 0
    @Published var trashCount: Int = 0
    @Published var isLoadingStats: Bool = false

    init() {
        // 从 UserDefaults 加载持久化数据
        self.totalDeletedPhotos = userDefaults.integer(forKey: totalDeletedPhotosKey)
        self.storageSpaceSavedBytes = userDefaults.integer(forKey: storageSpaceSavedBytesKey)
        self.currentPhotoCount = userDefaults.integer(forKey: lastPhotoCountKey)
        self.cleanupTimes = userDefaults.integer(forKey: cleanupTimesKey)
    }

    // MARK: - 格式化的统计信息

    /// 总照片数描述
    var totalPhotosText: String {
        formatNumber(currentPhotoCount)
    }

    /// 已删除照片数描述
    var deletedPhotosText: String {
        formatNumber(totalDeletedPhotos)
    }

    /// 待删除照片数描述
    var trashCountText: String {
        formatNumber(trashCount)
    }

    /// 已释放存储空间描述
    var storageSpaceSavedText: String {
        formatBytes(storageSpaceSavedBytes)
    }

    /// 便捷访问属性（与清理成就看板规范保持一致）
    var totalPhotosDeleted: Int { totalDeletedPhotos }
    var totalSpaceSaved: Int { storageSpaceSavedBytes }
    var cleanupCount: Int { max(cleanupTimes, totalDeletedPhotos > 0 ? 1 : 0) }

    // MARK: - 更新统计

    /// 更新实时统计（从 PhotoManager 获取）
    func updateStats(photoCount: Int, videoCount: Int, trash: Int) {
        currentPhotoCount = photoCount
        self.videoCount = videoCount
        trashCount = trash
        if photoCount > 0 {
            userDefaults.set(photoCount, forKey: lastPhotoCountKey)
        }
    }

    /// 批量记录删除操作（唯一统计口径：照片真实删除成功后调用）
    func recordDeletions(count: Int, totalSize: Int64) {
        totalDeletedPhotos += count
        storageSpaceSavedBytes += Int(totalSize)
        cleanupTimes += 1
        saveToDefaults()
    }

    /// 保存到 UserDefaults
    private func saveToDefaults() {
        userDefaults.set(totalDeletedPhotos, forKey: totalDeletedPhotosKey)
        userDefaults.set(storageSpaceSavedBytes, forKey: storageSpaceSavedBytesKey)
        userDefaults.set(cleanupTimes, forKey: cleanupTimesKey)
    }

    // MARK: - 格式化辅助

    private func formatNumber(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return String(localized: "Photo Count Unit \(formatted)")
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
