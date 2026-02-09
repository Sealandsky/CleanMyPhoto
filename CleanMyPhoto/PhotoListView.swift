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
    var scrollToPhotoID: String? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photoManager.displayedPhotos) { photo in
                        PhotoCell(photo: photo)
                            .id(photo.id)
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
            .onAppear {
                // 只在视图出现时滚动到指定位置，用户不会看到滚动动画
                if let photoID = scrollToPhotoID {
                    scrollToPhoto(proxy: proxy, photoID: photoID)
                }
            }
        }
    }

    private func scrollToPhoto(proxy: ScrollViewProxy, photoID: String) {
        // 不使用动画，直接定位，用户不会看到滚动过程
        proxy.scrollTo(photoID, anchor: .center)
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
