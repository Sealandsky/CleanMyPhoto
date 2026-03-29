//
//  AlbumListView.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI

struct AlbumListView: View {
    @ObservedObject var albumManager: AlbumManager
    let onAlbumSelect: (AlbumModel) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            if albumManager.isLoadingAlbums {
                ProgressView("Loading albums...")
                    .foregroundColor(.white)
            } else if albumManager.albums.isEmpty {
                emptyAlbumsView
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albumManager.albums) { album in
                        AlbumCell(album: album)
                            .onTapGesture {
                                onAlbumSelect(album)
                            }
                    }
                }
                .padding()
            }
        }
        .background(Color.black)
    }

    private var emptyAlbumsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Albums Found")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("You haven't created any albums yet.")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    AlbumListView(albumManager: AlbumManager(photoManager: PhotoManager())) { _ in }
}
