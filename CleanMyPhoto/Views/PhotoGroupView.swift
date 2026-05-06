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
        Group {
            if albumManager.isLoading && albumManager.allMonthAlbums.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Text(String(localized: "Loading..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(albumManager.yearAlbums) { yearAlbum in
                            Section {
                                if let months = albumManager.allMonthAlbums[yearAlbum.year], !months.isEmpty {
                                    LazyVGrid(columns: [
                                        GridItem(.flexible()),
                                        GridItem(.flexible())
                                    ], spacing: 12) {
                                        ForEach(months) { monthAlbum in
                                            MonthCardView(monthAlbum: monthAlbum)
                                                .onTapGesture {
                                                    onMonthSelect(monthAlbum)
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                            } header: {
                                HStack {
                                    Text(verbatim: "\(yearAlbum.year)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.leading, 0)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .background(Color.black)
        .task {
            await albumManager.fetchYearAlbums()
            await albumManager.fetchAllMonths()
        }
    }
}

// MARK: - Month Card View
struct MonthCardView: View {
    let monthAlbum: MonthAlbum

    var body: some View {
        PhotoCard {
            PhotoCardCover {
                if let thumbnail = monthAlbum.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else if let asset = monthAlbum.fetchResult?.firstObject ?? monthAlbum.assets.first {
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

            PhotoCardInfo(
                title: monthAlbum.monthName,
                subtitle: "\(monthAlbum.photoCount)\(String(localized: "photos"))"
            )
        }
    }
}

// MARK: - Month Photos View
struct SystemMonthPhotosView: View {
    let monthAlbum: MonthAlbum
    @ObservedObject var photoManager: PhotoManager
    let onPhotoSelect: (PhotoAsset) -> Void
    var scrollToPhotoID: String? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
    ]

    private var photos: [PhotoAsset] {
        monthAlbum.photoAssets
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        PhotoCell(photo: photo)
                            .id(photo.id)
                            .onTapGesture {
                                onPhotoSelect(photo)
                            }
                    }
                }
                .padding(.horizontal, 4)
            }
            .background(Color.black)
            .onAppear {
                if let photoID = scrollToPhotoID {
                    proxy.scrollTo(photoID, anchor: .center)
                }
            }
            .onChange(of: scrollToPhotoID) { oldValue, newValue in
                guard let photoID = newValue else { return }
                let photoExists = photos.contains(where: { $0.id == photoID })
                if photoExists {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withTransaction(Transaction(animation: nil)) {
                            proxy.scrollTo(photoID, anchor: .center)
                        }
                    }
                }
            }
        }
        .navigationTitle(monthAlbum.fullTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(monthAlbum.photoCount) \(String(localized: "photos"))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview("PhotoGroupView", body: {
    PhotoGroupView(
        albumManager: SystemAlbumManager(),
        photoManager: PhotoManager(),
        onMonthSelect: { _ in }
    )
})
