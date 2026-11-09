import Foundation
import CoreGraphics

// MARK: - Person Entity Model
/// 人物与面孔识别聚类实体
struct PersonEntity: Identifiable, Codable, Hashable {
    let id: String               // 实体唯一 ID (UUID)
    var name: String             // 自定义姓名 (如 "妈妈", 为空时在展示层展示占位)
    var photoIDs: [String]       // 该人物所属的照片 PHAsset localIdentifier 列表（降序）
    var avatarAssetID: String    // 封面大图 Asset ID
    var faceCropRect: CGRect     // 人脸标准化外接矩形 (UIKit 坐标系，[0, 1] 区间)
    var isFavorite: Bool = false
    var lastUpdated: Date = Date()

    /// 512维人脸特征向量序列化存储（Base64 字符串，便于 json 持久化）
    var featurePrintData: String? = nil

    /// 格式化展示名称：有姓名直接展示，无姓名根据序号展示「人物 %lld」或「未命名人物」
    func displayName(index: Int? = nil) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let idx = index {
            return String(format: String(localized: "Person %lld"), Int64(idx))
        }
        return String(localized: "Unnamed Person")
    }

    /// 照片总数
    var photoCount: Int {
        photoIDs.count
    }

    static func == (lhs: PersonEntity, rhs: PersonEntity) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.photoIDs == rhs.photoIDs &&
        lhs.avatarAssetID == rhs.avatarAssetID &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.faceCropRect == rhs.faceCropRect
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(photoIDs)
        hasher.combine(avatarAssetID)
        hasher.combine(isFavorite)
    }
}
