//
//  PhotoCell.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/9.
//

import SwiftUI
import Photos

// MARK: - Photo Cell
struct PhotoCell: View {
    let photo: PhotoAsset

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Photo
                AssetImage(
                    asset: photo.asset,
                    targetSize: CGSize(width: 150, height: 150),
                    contentMode: .fill
                )
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    PhotoCell(photo: PhotoAsset(asset: PHAsset()))
}
