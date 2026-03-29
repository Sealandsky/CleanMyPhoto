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
    let onBack: () -> Void
    var scrollToPhotoID: String? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
    ]

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    // 相簿标题
                    VStack(alignment: .leading, spacing: 12) {
                        Text(album.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        Text("\(albumManager.displayedAlbumPhotos.count) photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }

                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(albumManager.displayedAlbumPhotos) { photo in
                            PhotoCell(photo: photo)
                                .id(photo.id)
                                .onTapGesture {
                                    onPhotoSelect(photo)
                                }
                        }
                    }
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
            }

            // 返回按钮
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
