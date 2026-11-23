#if DEBUG
import SwiftUI
import Photos
import UIKit

// MARK: - Preview Asset Loader
public enum PreviewAssetLoader {
    private static var cache: [String: UIImage] = [:]

    public static func image(named name: String) -> UIImage? {
        if let cached = cache[name] {
            return cached
        }
        if let img = UIImage(named: name) {
            cache[name] = img
            return img
        }
        // Fallback: 预览画布沙盒直接读源文件，杜绝 Bundle 未链接导致的空白
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directPath = sourceDir.appendingPathComponent("Preview Content/Preview Assets.xcassets/\(name).imageset/\(name).jpg").path
        if FileManager.default.fileExists(atPath: directPath), let img = UIImage(contentsOfFile: directPath) {
            cache[name] = img
            return img
        }
        return nil
    }
}

// MARK: - Mock PHAsset
public final class MockPHAsset: PHAsset, @unchecked Sendable {
    private let _localIdentifier: String
    private let _pixelWidth: Int
    private let _pixelHeight: Int
    private let _creationDate: Date
    private let _isFavorite: Bool
    private let _mediaType: PHAssetMediaType

    public init(
        id: String,
        width: Int,
        height: Int,
        creationDate: Date = Date(),
        isFavorite: Bool = false,
        mediaType: PHAssetMediaType = .image
    ) {
        self._localIdentifier = id
        self._pixelWidth = width
        self._pixelHeight = height
        self._creationDate = creationDate
        self._isFavorite = isFavorite
        self._mediaType = mediaType
        super.init()
    }

    public override var localIdentifier: String { _localIdentifier }
    public override var pixelWidth: Int { _pixelWidth }
    public override var pixelHeight: Int { _pixelHeight }
    public override var creationDate: Date? { _creationDate }
    public override var isFavorite: Bool { _isFavorite }
    public override var mediaType: PHAssetMediaType { _mediaType }
}

// MARK: - PhotoAsset Mock Extensions
extension PhotoAsset {
    public static func mock(
        named name: String,
        width: Int = 1000,
        height: Int = 1000,
        isFavorite: Bool = false,
        mediaType: PHAssetMediaType = .image
    ) -> PhotoAsset {
        let asset = MockPHAsset(
            id: name,
            width: width,
            height: height,
            isFavorite: isFavorite,
            mediaType: mediaType
        )
        return PhotoAsset(asset: asset)
    }

    public static let mockCat = mock(named: "preview_cat", width: 1000, height: 688)
    public static let mockDog = mock(named: "preview_dog", width: 1000, height: 750)
    public static let mockPortrait1 = mock(named: "preview_portrait_1", width: 1000, height: 1250)
    public static let mockPortrait2 = mock(named: "preview_portrait_2", width: 1000, height: 1500)
    public static let mockPizza = mock(named: "preview_food_pizza", width: 1000, height: 1208)
    public static let mockCoffee = mock(named: "preview_food_coffee", width: 1000, height: 661)
    public static let mockMountain = mock(named: "preview_landscape_mountain", width: 1000, height: 667)
    public static let mockRoad = mock(named: "preview_landscape_road", width: 1000, height: 664)
    public static let mockForest = mock(named: "preview_landscape_forest", width: 1000, height: 596)
    public static let mockCityNight = mock(named: "preview_city_night", width: 1000, height: 1500)
    public static let mockRoom = mock(named: "preview_architecture_room", width: 1000, height: 668)
    public static let mockPlant = mock(named: "preview_nature_plant", width: 1000, height: 1500)
    public static let mockBeach = mock(named: "preview_sunset_beach", width: 1000, height: 665)
    public static let mockNote = mock(named: "preview_document_note", width: 1000, height: 751)
    public static let mockScreenshot = mock(named: "preview_screenshot_data", width: 1000, height: 667)
    public static let mockFlower = mock(named: "preview_flower_spring", width: 1000, height: 667)
    public static let mockCake = mock(named: "preview_dessert_cake", width: 1000, height: 735)
    public static let mockSky = mock(named: "preview_sky_clouds", width: 1000, height: 1288)

    public static let mockAllPhotos: [PhotoAsset] = [
        mockCat,
        mockPortrait1,
        mockMountain,
        mockPizza,
        mockCityNight,
        mockDog,
        mockCoffee,
        mockPlant,
        mockRoad,
        mockCake,
        mockForest,
        mockPortrait2,
        mockBeach,
        mockNote,
        mockFlower,
        mockRoom,
        mockSky,
        mockScreenshot
    ]
}

// MARK: - AlbumModel Mock
extension AlbumModel {
    public static let mockAlbums: [AlbumModel] = [
        AlbumModel(
            id: "mock_album_pets",
            title: "萌宠时光",
            assetCount: 128,
            coverAsset: PhotoAsset.mockCat.asset,
            stackAssets: [PhotoAsset.mockDog.asset, PhotoAsset.mockCat.asset]
        ),
        AlbumModel(
            id: "mock_album_travel",
            title: "旅行足迹",
            assetCount: 432,
            coverAsset: PhotoAsset.mockMountain.asset,
            stackAssets: [PhotoAsset.mockRoad.asset, PhotoAsset.mockMountain.asset]
        ),
        AlbumModel(
            id: "mock_album_food",
            title: "美食探店",
            assetCount: 86,
            coverAsset: PhotoAsset.mockPizza.asset,
            stackAssets: [PhotoAsset.mockCoffee.asset, PhotoAsset.mockCake.asset, PhotoAsset.mockPizza.asset]
        ),
        AlbumModel(
            id: "mock_album_portrait",
            title: "人物特写",
            assetCount: 215,
            coverAsset: PhotoAsset.mockPortrait1.asset,
            stackAssets: [PhotoAsset.mockPortrait2.asset, PhotoAsset.mockPortrait1.asset]
        )
    ]
}

// MARK: - OnThisDayYearGroup Mock
extension OnThisDayYearGroup {
    public static let mock = OnThisDayYearGroup(
        id: "mock_year_2023",
        year: 2023,
        relativeYearsAgo: 3,
        isMonthFallback: false,
        coverAsset: PhotoAsset.mockMountain,
        photoCount: PhotoAsset.mockAllPhotos.count,
        photos: PhotoAsset.mockAllPhotos,
        locationName: "瑞士因特拉肯"
    )
}

// MARK: - PhotoManager Mock
extension PhotoManager {
    public static var mock: PhotoManager {
        let manager = PhotoManager()
        manager.authorizationStatus = .authorized
        manager.trashedAssets = [
            PhotoAsset.mockScreenshot,
            PhotoAsset.mockNote
        ]
        return manager
    }
}
#endif
