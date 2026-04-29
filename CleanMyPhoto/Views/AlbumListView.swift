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
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            if albumManager.isLoadingAlbums {
                skeletonGrid
            } else if albumManager.albums.isEmpty {
                emptyAlbumsView
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(albumManager.albums) { album in
                        AlbumCell(album: album)
                            .onTapGesture {
                                onAlbumSelect(album)
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .background(Color.black)
    }

    // MARK: - Skeleton Grid
    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                AlbumCellSkeleton()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
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

// MARK: - Album Cell Skeleton
struct AlbumCellSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 16)
                    .frame(maxWidth: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(maxWidth: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .shimmering()
    }
}

#Preview {
    AlbumListView(albumManager: AlbumManager(photoManager: PhotoManager())) { _ in }
}
