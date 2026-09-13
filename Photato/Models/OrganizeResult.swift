import Foundation
import Photos

// MARK: - Organize Category

enum OrganizeCategory: String, CaseIterable, Identifiable, Sendable {
    case similar
    case duplicates
    case screenshots
    case livePhotos
    case videos
    case lowQuality
    case largeFiles
    case blurry
    case poorFace

    var id: String { rawValue }

    var localizedText: String {
        switch self {
        case .duplicates:
            return String(localized: "Duplicates")
        case .similar:
            return String(localized: "Similar")
        case .screenshots:
            return String(localized: "Screenshots")
        case .livePhotos:
            return String(localized: "Live Photos")
        case .videos:
            return String(localized: "Videos")
        case .lowQuality:
            return String(localized: "Low Quality")
        case .largeFiles:
            return String(localized: "Large Files")
        case .blurry:
            return String(localized: "Blurry")
        case .poorFace:
            return String(localized: "Blurry Faces")
        }
    }

    var icon: String {
        switch self {
        case .duplicates:
            return "doc.on.doc"
        case .similar:
            return "app.background.dotted"
        case .screenshots:
            return "camera.viewfinder"
        case .livePhotos:
            return "livephoto"
        case .videos:
            return "video"
        case .lowQuality:
            return "exclamationmark.triangle"
        case .largeFiles:
            return "externaldrive"
        case .blurry:
            return "water.waves"
        case .poorFace:
            return "face.dashed"
        }
    }
}

// MARK: - Organize Group (lightweight scan result)

struct OrganizeScanGroup: Identifiable, Sendable {
    let id: String
    let category: OrganizeCategory
    let title: String
    let localIdentifiers: [String]
    let potentialSpaceSaved: Int64
    let sampleDate: Date?

    /// nonisolated：扫描分组在后台任务（相似/重复聚类）中构造，纯值类型可安全跨隔离域
    nonisolated init(category: OrganizeCategory, title: String, localIdentifiers: [String], potentialSpaceSaved: Int64 = 0, sampleDate: Date? = nil) {
        self.id = UUID().uuidString
        self.category = category
        self.title = title
        self.localIdentifiers = localIdentifiers
        self.potentialSpaceSaved = potentialSpaceSaved
        self.sampleDate = sampleDate
    }
}

// MARK: - Group Display (for similar/duplicates grouped layout)

struct OrganizeGroupDisplay: Identifiable {
    let id: String
    let title: String
    let localIdentifiers: [String]
    var loadedPhotos: [PhotoAsset] = []
    var bestPhotoId: String? = nil
    var totalSize: Int64 = 0
    var sampleDate: Date? = nil
}

// MARK: - Category Page State (pagination)

struct OrganizeCategoryPageState {
    var allIdentifiers: [String] = []
    var loadedPhotos: [PhotoAsset] = []
    var currentPage: Int = 0
    var hasMore: Bool = true
    var isLoading: Bool = false

    var groups: [OrganizeGroupDisplay] = []

    static let pageSize = 50
    static let groupBatchSize = 10
}

// MARK: - Organize Destination

enum OrganizeDestination: Hashable {
    case categoryResults(OrganizeCategory)
}

// MARK: - Cache Summary (JSON file for instant load)

struct OrganizeCacheGroupItem: Codable, Sendable {
    let localIdentifiers: [String]
    let sampleDate: Date?
}

struct OrganizeCacheSummary: Codable {
    let version: Int
    let timestamp: Date
    let totalPhotoCount: Int
    let screenshotIds: [String]
    let livePhotoIds: [String]
    let videoIds: [String]
    let largeFileIds: [String]
    let largeFileTotalSize: Int64
    let lowQualityIds: [String]
    let similarGroups: [OrganizeCacheGroupItem]
    let duplicateGroups: [OrganizeCacheGroupItem]
    let blurryIds: [String]
    let poorFaceIds: [String]

    static let currentVersion = 8
    static let fileName = "OrganizeCache.json"
}

// MARK: - Byte Formatter

enum ByteFormatter {
    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
