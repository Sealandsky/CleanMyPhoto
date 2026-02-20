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
                }

                // Loading indicator at bottom
                if photoManager.isLoadingMore {
                    ProgressView()
                        .foregroundColor(.white)
                        .padding()
                }
            }
            .background(Color("AccentBg"))
            .onAppear {
                // 只在视图出现时滚动到指定位置
                if let photoID = scrollToPhotoID {
                    scrollToPhoto(proxy: proxy, photoID: photoID)
                }
            }
            .onChange(of: scrollToPhotoID) { oldValue, newValue in
                guard let photoID = newValue else { return }

                // 验证照片是否仍然存在
                let photoExists = photoManager.displayedPhotos.contains(where: { $0.id == photoID })

                if photoExists {
                    // 延迟滚动，确保 LazyVGrid 已经渲染完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withTransaction(Transaction(animation: nil)) {
                            proxy.scrollTo(photoID, anchor: .center)
                        }
                    }
                } else {
                    print("⚠️ Photo \(photoID) no longer exists, skipping scroll")
                }
            }
        }
    }

    private func scrollToPhoto(proxy: ScrollViewProxy, photoID: String) {
        // 直接滚动到照片位置
        proxy.scrollTo(photoID, anchor: .center)
    }
}

// MARK: - Preview
#Preview {
    PhotoListView(photoManager: PhotoManager()) { _ in }
}
