import Foundation

/// 照片清理完成结果模型，记录单次清理删除的照片数量与释放的存储空间
struct CleanupResult: Identifiable, Equatable, Sendable {
    let id: UUID
    let deletedCount: Int
    let freedBytes: Int64

    init(id: UUID = UUID(), deletedCount: Int, freedBytes: Int64) {
        self.id = id
        self.deletedCount = deletedCount
        self.freedBytes = freedBytes
    }

    /// 格式化后的释放存储空间大小（如 "128 MB"、"1.2 GB"）
    var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useAll]
        return formatter.string(fromByteCount: max(0, freedBytes))
    }

    /// 格式化后的照片数量描述（如 "12 张照片" / "12 Photos"）
    var formattedCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let numStr = formatter.string(from: NSNumber(value: deletedCount)) ?? "\(deletedCount)"
        return String(localized: "Photo Count Unit \(numStr)")
    }
}
