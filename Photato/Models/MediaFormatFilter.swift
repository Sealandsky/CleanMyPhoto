import Foundation
import Photos

// MARK: - Media Format Filter
enum MediaFormatFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case video
    case livePhoto
    case screenshot

    var id: String { rawValue }

    var localizedText: String {
        switch self {
        case .all:
            return String(localized: "All", defaultValue: "全部")
        case .video:
            return String(localized: "Videos", defaultValue: "视频")
        case .livePhoto:
            return String(localized: "Live Photos (Filter)", defaultValue: "实况")
        case .screenshot:
            return String(localized: "Screenshots", defaultValue: "屏幕快照")
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .video:
            return "video"
        case .livePhoto:
            return "livephoto"
        case .screenshot:
            return "camera.viewfinder"
        }
    }

    nonisolated var predicate: NSPredicate? {
        switch self {
        case .all:
            return NSPredicate(
                format: "mediaType IN %@",
                [PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue]
            )
        case .video:
            return NSPredicate(
                format: "mediaType == %d",
                PHAssetMediaType.video.rawValue
            )
        case .livePhoto:
            return NSPredicate(
                format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaSubtype.photoLive.rawValue
            )
        case .screenshot:
            return NSPredicate(
                format: "(mediaSubtypes & %d) != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
        }
    }
}
