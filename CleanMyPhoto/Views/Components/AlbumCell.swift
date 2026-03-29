//
//  AlbumCell.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI
import Photos

struct AlbumCell: View {
    let album: AlbumModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面图（使用缓存）
            ZStack {
                if let coverAsset = album.coverAsset {
                    CachedAlbumCoverView(
                        albumID: album.id,
                        coverAsset: coverAsset,
                        targetSize: CGSize(width: 400, height: 400)
                    )
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        )
                }
            }

            // 相簿标题和数量
            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\(album.assetCount) \(String(localized: "photos"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .background(Color.black)
    }
}
