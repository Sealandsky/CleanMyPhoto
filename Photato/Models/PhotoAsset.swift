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
