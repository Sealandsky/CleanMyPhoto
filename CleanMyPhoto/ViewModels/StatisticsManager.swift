//
//  StatisticsManager.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/4/30.
//

import SwiftUI
import Combine

class StatisticsManager: ObservableObject {
    private let userDefaults = UserDefaults.standard

    // 持久化数据键
    private let totalDeletedPhotosKey = "totalDeletedPhotos"
    private let storageSpaceSavedBytesKey = "storageSpaceSavedBytes"

    // 持久化数据
    @Published private(set) var totalDeletedPhotos: Int = 0
    @Published private(set) var storageSpaceSavedBytes: Int = 0

    // 实时数据
    @Published var currentPhotoCount: Int = 0
    @Published var videoCount: Int = 0
    @Published var trashCount: Int = 0
    @Published var isLoadingStats: Bool = false

    init() {
        // 从 UserDefaults 加载持久化数据
        self.totalDeletedPhotos = userDefaults.integer(forKey: totalDeletedPhotosKey)
        self.storageSpaceSavedBytes = userDefaults.integer(forKey: storageSpaceSavedBytesKey)
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

    // MARK: - 更新统计

    /// 更新实时统计（从 PhotoManager 获取）
    func updateStats(photoCount: Int, videoCount: Int, trash: Int) {
        currentPhotoCount = photoCount
        self.videoCount = videoCount
        trashCount = trash
    }

    /// 记录删除操作
    func recordDeletion(assetSize: Int64) {
        totalDeletedPhotos += 1
        storageSpaceSavedBytes += Int(assetSize)
        saveToDefaults()
    }

    /// 批量记录删除操作
    func recordDeletions(count: Int, totalSize: Int64) {
        totalDeletedPhotos += count
        storageSpaceSavedBytes += Int(totalSize)
        saveToDefaults()
    }

    /// 保存到 UserDefaults
    private func saveToDefaults() {
        userDefaults.set(totalDeletedPhotos, forKey: totalDeletedPhotosKey)
        userDefaults.set(storageSpaceSavedBytes, forKey: storageSpaceSavedBytesKey)
    }

    // MARK: - 格式化辅助

    private func formatNumber(_ count: Int) -> String {
        return "\(count)"
    }

    private func formatBytes(_ bytes: Int) -> String {
        let bytes = Int64(bytes)
        if bytes >= 1_000_000_000 {
            let gb = Double(bytes) / 1_000_000_000.0
            return String(format: "%.2f GB", gb)
        } else if bytes >= 1_000_000 {
            let mb = Double(bytes) / 1_000_000.0
            return String(format: "%.1f MB", mb)
        } else if bytes >= 1000 {
            let kb = Double(bytes) / 1000.0
            return String(format: "%.0f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }
}
