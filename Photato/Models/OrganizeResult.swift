import Foundation
import Photos

// MARK: - Organize Category

enum OrganizeCategory: String, CaseIterable, Identifiable {
    case similar
    case duplicates
    case screenshots
    case livePhotos
    case videos
    case lowQuality
    case largeFiles

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
        }
    }

    var icon: String {
        switch self {
        case .duplicates:
            return "doc.on.doc"
        case .similar:
            return "photo.stack"
        case .screenshots:
            return "iphone"
        case .livePhotos:
            return "livephoto"
        case .videos:
            return "video"
        case .lowQuality:
            return "exclamationmark.triangle"
        case .largeFiles:
            return "externaldrive"
        }
    }
}

// MARK: - Organize Group (lightweight scan result)

struct OrganizeScanGroup: Identifiable {
    let id: String
    let category: OrganizeCategory
    let title: String
    let localIdentifiers: [String]
    let potentialSpaceSaved: Int64

    init(category: OrganizeCategory, title: String, localIdentifiers: [String], potentialSpaceSaved: Int64 = 0) {
        self.id = UUID().uuidString
        self.category = category
        self.title = title
        self.localIdentifiers = localIdentifiers
        self.potentialSpaceSaved = potentialSpaceSaved
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
}

// MARK: - Organize Destination

enum OrganizeDestination: Hashable {
    case categoryResults(OrganizeCategory)
}

// MARK: - Cache Summary (JSON file for instant load)

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
    let similarGroups: [[String]]
    let duplicateGroups: [[String]]

    static let currentVersion = 2
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
