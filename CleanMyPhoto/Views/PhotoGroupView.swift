//
//  PhotoGroupView.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI
import Photos

struct PhotoGroupView: View {
    @ObservedObject var albumManager: SystemAlbumManager
    @ObservedObject var photoManager: PhotoManager
    let onMonthSelect: (MonthAlbum) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // 左侧年份列表
            YearListView(
                yearAlbums: albumManager.yearAlbums,
                selectedYear: albumManager.selectedYear,
                onYearSelect: { year in
                    albumManager.selectedYear = year
                    Task {
                        await albumManager.loadMonthAlbumsForYear(year)
                    }
                }
            )
            .frame(width: 120)
            .background(Color.black.opacity(0.3))

            // 右侧月份列表
            if albumManager.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Text(String(localized: "加载中..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                MonthListView(
                    monthAlbums: albumManager.monthAlbums,
                    onMonthSelect: { monthAlbum in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            onMonthSelect(monthAlbum)
                        }
                    }
                )
            }
        }
        .background(Color.black)
        .task {
            await albumManager.fetchYearAlbums()
        }
    }
}

// MARK: - Year List View (只显示年份文字)
struct YearListView: View {
    let yearAlbums: [YearAlbum]
    let selectedYear: Int?
    let onYearSelect: (Int) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(yearAlbums) { album in
                    Button {
                        onYearSelect(album.year)
                    } label: {
                        VStack(spacing: 8) {
                            Text("\(album.year)")
                                .font(.system(size: 20, weight: album.year == selectedYear ? .bold : .regular))
                                .foregroundColor(album.year == selectedYear ? .white : .secondary)

                            Text("\(album.photoCount)\(String(localized: "photos"))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            album.year == selectedYear ?
                            Color.white.opacity(0.1) : Color.clear
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

// MARK: - Month List View
struct MonthListView: View {
    let monthAlbums: [MonthAlbum]
    let onMonthSelect: (MonthAlbum) -> Void

    var body: some View {
        Group {
            if monthAlbums.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "请选择年份"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(monthAlbums) { monthAlbum in
                            MonthCardView(monthAlbum: monthAlbum)
                                .onTapGesture {
                                    onMonthSelect(monthAlbum)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.black)
    }
}

// MARK: - Month Card View (使用系统封面)
struct MonthCardView: View {
    let monthAlbum: MonthAlbum

    var body: some View {
        VStack(spacing: 0) {
            // 系统封面（大图）
            GeometryReader { geometry in
                ZStack {
                    if let thumbnail = monthAlbum.thumbnail {
                        // 优先使用缓存的缩略图
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else if let asset = monthAlbum.fetchResult?.firstObject ?? monthAlbum.assets.first {
                        // 如果没有缓存，使用 AssetImage 加载
                        AssetImage(
                            asset: asset,
                            targetSize: CGSize(width: 400, height: 400),
                            contentMode: .fill
                        )
                        .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                            )
                    }
                }
                .frame(width: geometry.size.width, height: 150)
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipped()
            }
            .frame(height: 150)

            // 月份信息
            VStack(spacing: 4) {
                Text(monthAlbum.monthName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(monthAlbum.photoCount)\(String(localized: "photos"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Month Photos View
struct SystemMonthPhotosView: View {
    let monthAlbum: MonthAlbum
    @ObservedObject var photoManager: PhotoManager
    let onPhotoSelect: (PhotoAsset) -> Void
    let onBack: () -> Void
    var scrollToPhotoID: String? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
    ]

    // 将 PHAsset 转换为 PhotoAsset
    private var photos: [PhotoAsset] {
        // 优先从 fetchResult 获取，否则从 assets 获取
        if let fetchResult = monthAlbum.fetchResult {
            return (0..<fetchResult.count).compactMap { index in
                guard index < fetchResult.count else { return nil }
                let asset = fetchResult.object(at: index)
                return PhotoAsset(asset: asset)
            }
        } else {
            return monthAlbum.assets.map { PhotoAsset(asset: $0) }
        }
    }

    var body: some View {
        ZStack {
            // 主要内容区域
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // 标题区域
                        VStack(alignment: .leading, spacing: 12) {
                            Text(monthAlbum.fullTitle)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                                .padding(.top, 8)

                            Text("\(monthAlbum.photoCount) \(String(localized: "photos"))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }

                        // 照片网格
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(photos) { photo in
                                PhotoCell(photo: photo)
                                    .id(photo.id)
                                    .onTapGesture {
                                        onPhotoSelect(photo)
                                    }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .background(Color.black)
                .onAppear {
                    if let scrollToID = scrollToPhotoID {
                        proxy.scrollTo(scrollToID, anchor: .center)
                    }
                }
            }

            // 浮动返回按钮
            VStack {
                HStack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.8))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding()

                Spacer()
            }
        }
    }
}

// MARK: - Previews
#Preview("PhotoGroupView - Full View", body: {
    PhotoGroupView(
        albumManager: SystemAlbumManager(),
        photoManager: PhotoManager(),
        onMonthSelect: { _ in }
    )
})

#Preview("SystemMonthPhotosView", body: {
    SystemMonthPhotosView(
        monthAlbum: MonthAlbum(
            collection: nil,
            fetchResult: nil,
            assets: [],
            year: 2025,
            month: 3,
            thumbnail: nil
        ),
        photoManager: PhotoManager(),
        onPhotoSelect: { _ in },
        onBack: {}
    )
})

#Preview("PhotoGroupView - With Sample Data", body: {
    PhotoGroupViewWithSampleData()
})

#Preview("YearListView", body: {
    let sampleYears = [
        YearAlbum(collection: nil, fetchResult: nil, assets: [], year: 2026, thumbnail: nil),
        YearAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, thumbnail: nil),
        YearAlbum(collection: nil, fetchResult: nil, assets: [], year: 2024, thumbnail: nil),
        YearAlbum(collection: nil, fetchResult: nil, assets: [], year: 2023, thumbnail: nil),
    ]

    YearListView(
        yearAlbums: sampleYears,
        selectedYear: 2025,
        onYearSelect: { _ in }
    )
    .frame(width: 120, height: 500)
    .background(Color.black)
})

#Preview("MonthListView - Empty", body: {
    MonthListView(
        monthAlbums: [],
        onMonthSelect: { _ in }
    )
    .frame(width: 300, height: 500)
})

#Preview("MonthListView - With Data", body: {
    let sampleMonths = [
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 12, thumbnail: nil),
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 11, thumbnail: nil),
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 10, thumbnail: nil),
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 9, thumbnail: nil),
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 8, thumbnail: nil),
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 7, thumbnail: nil),
    ]

    MonthListView(
        monthAlbums: sampleMonths,
        onMonthSelect: { _ in }
    )
    .frame(width: 300, height: 500)
})

#Preview("MonthCardView", body: {
    let sampleMonth = MonthAlbum(
        collection: nil,
        fetchResult: nil,
        assets: [],
        year: 2025,
        month: 3,
        thumbnail: nil
    )

    MonthCardView(monthAlbum: sampleMonth)
        .frame(width: 150)
        .padding()
    .background(Color.black)
})

// MARK: - Preview Helper Views
/// 用于预览的完整视图，包含示例数据
struct PhotoGroupViewWithSampleData: View {
    @State private var selectedYear: Int? = 2025

    private let sampleYears = [
        YearAlbum(collection: nil, fetchResult: nil, assets: [], year: 2026, thumbnail: nil),
        YearAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, thumbnail: nil),
        YearAlbum(collection: nil, fetchResult: nil, assets: [], year: 2024, thumbnail: nil),
        YearAlbum(collection: nil, fetchResult: nil, assets: [], year: 2023, thumbnail: nil),
    ]

    private let sampleMonths = [
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 12, thumbnail: nil),
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 11, thumbnail: nil),
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 10, thumbnail: nil),
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 9, thumbnail: nil),
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 8, thumbnail: nil),
        MonthAlbum(collection: nil, fetchResult: nil, assets: [], year: 2025, month: 7, thumbnail: nil),
    ]

    var body: some View {
        // 显示年月列表（有数据）
        HStack(spacing: 0) {
            // 左侧年份列表
            YearListView(
                yearAlbums: sampleYears,
                selectedYear: selectedYear,
                onYearSelect: { year in
                    selectedYear = year
                }
            )
            .frame(width: 120)
            .background(Color.black.opacity(0.3))

            // 右侧月份列表
            MonthListView(
                monthAlbums: sampleMonths,
                onMonthSelect: { _ in }
            )
        }
    }
}
