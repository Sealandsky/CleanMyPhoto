import Foundation
import Photos

// MARK: - Media Type
enum AssetMediaType {
    case image
    case video
    case livePhoto
    case gif
    case screenshot
}

// MARK: - Photo Asset Model
struct PhotoAsset: Identifiable, Equatable {
    let id: String
    let asset: PHAsset
    let mediaType: AssetMediaType
    var isFavorite: Bool

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.mediaType = Self.detectMediaType(asset)
        self.isFavorite = asset.isFavorite
    }

    static func == (lhs: PhotoAsset, rhs: PhotoAsset) -> Bool {
        lhs.id == rhs.id && lhs.isFavorite == rhs.isFavorite
    }

    // MARK: - Media Type Detection

    private static func detectMediaType(_ asset: PHAsset) -> AssetMediaType {
        switch asset.mediaType {
        case .image:
            if asset.mediaSubtypes.contains(.photoLive) {
                return .livePhoto
            }
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                return .screenshot
            }
            if isGIF(asset) {
                return .gif
            }
            return .image
        case .video:
            return .video
        default:
            return .image
        }
    }

    private static func isGIF(_ asset: PHAsset) -> Bool {
        PHAssetResource.assetResources(for: asset)
            .contains { $0.uniformTypeIdentifier == "com.compuserve.gif" }
    }

    // MARK: - Original Aspect Ratio

    /// 原始宽高比（宽/高），直接读同步元数据，无 IO 开销。
    /// 元数据异常时回退默认比例；钳制到 [1/3, 3]，常规照片完全原比例显示，
    /// 极端全景/长截图仅轻度裁剪以维持瀑布流各列视觉均衡。
    var pixelAspectRatio: CGFloat {
        let width = asset.pixelWidth
        let height = asset.pixelHeight
        guard width > 0, height > 0 else { return GridColumnHelper.defaultRatio }
        return min(max(CGFloat(width) / CGFloat(height), 1.0 / 3.0), 3.0)
    }

    // MARK: - Video Duration

    var videoDuration: String? {
        guard asset.mediaType == .video else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter.string(from: asset.duration)
    }
}
