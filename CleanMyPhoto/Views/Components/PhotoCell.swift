//
//  PhotoCell.swift
//  CleanMyPhoto
//
//  Created by 陈嘉华 on 2026/2/9.
//

import SwiftUI
import Photos

// MARK: - Photo Cell
struct PhotoCell: View {
    let photo: PhotoAsset

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                AssetImage(
                    asset: photo.asset,
                    targetSize: CGSize(width: 400, height: 400),
                    contentMode: .fill
                )
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                mediaBadge
            }
            .overlay(alignment: .bottomLeading) {
                if photo.isFavorite {
                    favoriteBadge
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Media Badge

    @ViewBuilder
    private var mediaBadge: some View {
        switch photo.mediaType {
        case .video:
            videoBadge
        case .livePhoto:
            livePhotoBadge
        case .gif:
            textBadge("GIF", .purple)
        case .screenshot:
            textBadge("SCREEN", .orange)
        case .image:
            EmptyView()
        }
    }

    private var videoBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill")
                .font(.system(size: 10))
            if let duration = photo.videoDuration {
                Text(duration)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(6)
    }

    private var favoriteBadge: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(6)
    }

    private var livePhotoBadge: some View {
        Image(systemName: "livephoto")
            .font(.system(size: 14))
            .foregroundColor(.white)
            .padding(2)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
    }

    private func iconBadge(_ iconName: String, _ color: Color) -> some View {
        Image(systemName: iconName)
            .font(.system(size: 16))
            .foregroundColor(.white)
            .padding(7)
            .background(color, in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
    }

    private func textBadge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color, in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
    }
}

#Preview {
    PhotoCell(photo: PhotoAsset(asset: PHAsset()))
}
