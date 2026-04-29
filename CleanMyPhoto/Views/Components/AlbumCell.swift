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
            GeometryReader { geometry in
                ZStack {
                    if let coverAsset = album.coverAsset {
                        CachedAlbumCoverView(
                            albumID: album.id,
                            coverAsset: coverAsset,
                            targetSize: CGSize(width: 400, height: 400)
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
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(height: 150)
            .clipped()

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
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}
