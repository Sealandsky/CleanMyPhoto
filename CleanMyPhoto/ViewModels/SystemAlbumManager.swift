//
//  SystemAlbumManager.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import Photos
import SwiftUI
import Combine

@MainActor
class SystemAlbumManager: NSObject, ObservableObject {
    @Published var yearAlbums: [YearAlbum] = []
    @Published var isLoading = false
    @Published var selectedYear: Int? = nil
    @Published var monthAlbums: [MonthAlbum] = []

    private let imageManager = PHCachingImageManager()
    private var thumbnailSize: CGSize = .zero

    override init() {
        super.init()
        thumbnailSize = CGSize(width: 150 * ScreenSizeHelper.screenScale, height: 150 * ScreenSizeHelper.screenScale)
    }

    /// 加载所有年份相册
    func fetchYearAlbums() async {
        isLoading = true
        defer { isLoading = false }

        print("📅 Starting to fetch year albums...")

        // 查询所有照片
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]

        let allAssets = PHAsset.fetchAssets(with: options)
        print("📸 Total photos: \(allAssets.count)")

        // 按年份分组照片
        var yearAssets: [Int: [PHAsset]] = [:]
        allAssets.enumerateObjects { asset, _, _ in
            if let creationDate = asset.creationDate {
                let year = Calendar.current.component(.year, from: creationDate)
                if yearAssets[year] == nil {
                    yearAssets[year] = []
                }
                yearAssets[year]?.append(asset)
            }
        }

        print("📅 Found \(yearAssets.count) years")

        // 为每个年份创建 YearAlbum
        var albums: [YearAlbum] = []
        for (year, assets) in yearAssets.sorted(by: { $0.key > $1.key }) {
            let album = YearAlbum(
                collection: nil,
                fetchResult: nil,
                assets: assets,
                year: year,
                thumbnail: nil
            )

            albums.append(album)

            // 异步加载缩略图
            Task {
                await self.loadYearThumbnail(for: album)
            }
        }

        self.yearAlbums = albums

        // 如果还没有选中的年份，默认选中当前年份
        if selectedYear == nil {
            let currentYear = Calendar.current.component(.year, from: Date())
            if albums.contains(where: { $0.year == currentYear }) {
                selectedYear = currentYear
            } else {
                // 如果当前年份不存在（没有照片），使用最新年份
                selectedYear = albums.first?.year
            }
            print("✅ Selected year: \(selectedYear ?? 0)")
        }

        // 加载选中年份的月份
        if let year = selectedYear {
            print("📅 Loading months for year: \(year)")
            await loadMonthAlbumsForYear(year)
        }
    }

    /// 加载年份缩略图
    private func loadYearThumbnail(for album: YearAlbum) async {
        // 优先从 fetchResult 获取，否则从 assets 获取
        guard let asset = album.fetchResult?.firstObject ?? album.assets.first else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        // 使用 UnsafeContinuation 并确保只 resume 一次
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            var isResumed = false

            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 80, height: 80),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if let image = image {
                    Task { @MainActor in
                        // 创建新的数组副本以确保视图更新
                        self.yearAlbums = self.yearAlbums.map { yearAlbum in
                            if yearAlbum.id == album.id {
                                var updated = yearAlbum
                                updated.thumbnail = image
                                return updated
                            }
                            return yearAlbum
                        }
                    }
                }

                // 只在第一次调用时 resume
                if !isResumed {
                    isResumed = true
                    continuation.resume()
                }
            }
        }
    }

    /// 获取指定年份的月份相册（只显示有照片的月份）
    func loadMonthAlbumsForYear(_ year: Int) async {
        print("📅 loadMonthAlbumsForYear called for year: \(year)")

        // 创建日期范围（该年的1月1日到12月31日）
        let calendar = Calendar.current
        guard let startDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let endDate = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59)) else {
            print("⚠️ Failed to create date range for year: \(year)")
            return
        }

        // 查询该年的所有照片
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", startDate as NSDate, endDate as NSDate)

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        print("📸 Found \(fetchResult.count) photos for year \(year)")

        // 按月份分组照片
        var monthAssets: [Int: [PHAsset]] = [:]

        fetchResult.enumerateObjects { asset, _, _ in
            if let creationDate = asset.creationDate {
                let month = calendar.component(.month, from: creationDate)
                if monthAssets[month] == nil {
                    monthAssets[month] = []
                }
                monthAssets[month]?.append(asset)
            }
        }

        print("📅 Found \(monthAssets.count) months with photos")

        // 只为有照片的月份创建 MonthAlbum
        var albums: [MonthAlbum] = []
        for (month, assets) in monthAssets.sorted(by: { $0.key > $1.key }) {
            let album = MonthAlbum(
                collection: nil,
                fetchResult: nil,
                assets: assets,
                year: year,
                month: month,
                thumbnail: nil
            )

            albums.append(album)
        }

        // 按月份倒序排序（12月在前）
        self.monthAlbums = albums.sorted(by: { $0.month > $1.month })

        print("✅ Created \(self.monthAlbums.count) month albums")

        // 异步加载缩略图（不阻塞主线程）
        for album in self.monthAlbums {
            Task {
                await self.loadMonthThumbnail(for: album)
            }
        }
    }

    /// 加载月份缩略图并缓存
    private func loadMonthThumbnail(for album: MonthAlbum) async {
        // 优先从 fetchResult 获取，否则从 assets 获取
        guard let asset = album.fetchResult?.firstObject ?? album.assets.first else {
            print("⚠️ No asset found for month: \(album.monthName)")
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        print("📸 Loading thumbnail for \(album.monthName)...")

        // 使用 UnsafeContinuation 允许多次调用，但只 resume 一次
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            var isResumed = false

            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 400, height: 400),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let image = image {
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    if !isDegraded {
                        print("✅ Loaded thumbnail for \(album.monthName)")
                        Task { @MainActor in
                            // 创建新的数组副本以确保视图更新
                            self.monthAlbums = self.monthAlbums.map { monthAlbum in
                                if monthAlbum.id == album.id {
                                    var updated = monthAlbum
                                    updated.thumbnail = image
                                    return updated
                                }
                                return monthAlbum
                            }
                        }
                    }
                } else {
                    print("❌ Failed to load thumbnail for \(album.monthName)")
                }

                // 只在第一次调用时 resume
                if !isResumed {
                    isResumed = true
                    continuation.resume()
                }
            }
        }
    }
}
