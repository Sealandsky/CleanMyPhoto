//
//  CachedAlbumCoverView.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI
import Photos
import UIKit

// MARK: - Cached Album Cover View
struct CachedAlbumCoverView: View {
    let albumID: String
    let coverAsset: PHAsset
    let targetSize: CGSize

    @StateObject private var cache = AlbumCoverCache.shared
    @State private var displayImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                // 第一次加载且没有缓存时显示 loading
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                // 占位图
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    )
            }
        }
        .onAppear {
            loadCover()
        }
    }

    private func loadCover() {
        // 1. 尝试从缓存获取
        if let cachedImage = cache.getCachedCover(for: albumID) {
            displayImage = cachedImage

            // 2. 检查是否需要更新（封面是否变化）
            if cache.needsUpdate(for: albumID, currentCoverAsset: coverAsset) {
                // 在后台静默更新
                refreshCover()
            }
        } else {
            // 3. 没有缓存，需要加载
            isLoading = true
            refreshCover()
        }
    }

    private func refreshCover() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: coverAsset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [self] resultImage, info in
            Task { @MainActor in
                guard let image = resultImage else {
                    isLoading = false
                    return
                }

                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false

                if !isDegraded {
                    // 更新显示
                    displayImage = image
                    isLoading = false

                    // 更新缓存
                    cache.updateCache(for: albumID, image: image, asset: coverAsset)
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        Text("Cached Album Cover View")
            .font(.headline)

        // 注意：这个预览需要实际的 PHAsset 才能工作
        // 在实际使用时，AlbumCell 会调用这个组件
    }
}
