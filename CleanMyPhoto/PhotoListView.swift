//
//  PhotoListView.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/9.
//

import SwiftUI
import Photos

struct PhotoListView: View {
    @ObservedObject var photoManager: PhotoManager
    let onPhotoSelect: (PhotoAsset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(photoManager.displayedPhotos) { photo in
                    PhotoCell(photo: photo)
                        .onTapGesture {
                            onPhotoSelect(photo)
                        }
                        .onAppear {
                            // 当最后一张图片出现时，加载更多
                            if photo.id == photoManager.displayedPhotos.last?.id {
                                Task {
                                    await photoManager.fetchMorePhotos()
                                }
                            }
                        }
                }

                // Loading indicator at bottom
                if photoManager.isLoadingMore {
                    ProgressView()
                        .foregroundColor(.white)
                        .padding()
                }
            }
        }
        .background(Color.black)
    }
}

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
                
                .clipped()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Preview
#Preview {
    PhotoListView(photoManager: PhotoManager()) { _ in }
}
