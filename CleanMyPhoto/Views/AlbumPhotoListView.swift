//
//  AlbumPhotoListView.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI

struct AlbumPhotoListView: View {
    @ObservedObject var albumManager: AlbumManager
    @ObservedObject var photoManager: PhotoManager
    let album: AlbumModel
    let onPhotoSelect: (PhotoAsset) -> Void
    var scrollToPhotoID: String? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(albumManager.displayedAlbumPhotos) { photo in
                        PhotoCell(photo: photo)
                            .id(photo.id)
                            .onTapGesture {
                                onPhotoSelect(photo)
                            }
                    }
                }
                .padding(.horizontal, 2)
            }
            .background(Color.black)
            .onChange(of: scrollToPhotoID) { oldValue, newValue in
                guard let photoID = newValue else { return }
                let photoExists = albumManager.displayedAlbumPhotos.contains(where: { $0.id == photoID })

                if photoExists {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withTransaction(Transaction(animation: nil)) {
                            proxy.scrollTo(photoID, anchor: .center)
                        }
                    }
                }
            }
            .onAppear {
                if let photoID = scrollToPhotoID {
                    proxy.scrollTo(photoID, anchor: .center)
                }
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(albumManager.displayedAlbumPhotos.count) \(String(localized: "photos"))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
