//
//  PHAsset+Image.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/7.
//

import SwiftUI
import Photos

// MARK: - SwiftUI Image View for PHAsset
struct AssetImage: View {
    let asset: PHAsset
    let targetSize: CGSize
    let contentMode: ContentMode

    @State private var image: UIImage?
    @State private var isLoading = true

    init(asset: PHAsset, targetSize: CGSize, contentMode: ContentMode = .fit) {
        self.asset = asset
        self.targetSize = targetSize
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: asset.localIdentifier) { _, _ in
            image = nil
            isLoading = true
            loadImage()
        }
    }

    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.progressHandler = { progress, _, _, _ in
            // 可选：显示加载进度
            if progress >= 1.0 {
                print("✅ Image fully loaded")
            }
        }

        // 使用 PHImageManagerMaximumSize 获取原图尺寸
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { [self] resultImage, info in
            Task { @MainActor in
                if let img = resultImage {
                    self.image = img

                    // 检查是否是缩略图（degraded）
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    if !isDegraded {
                        self.isLoading = false
                    }
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    print("❌ Image loading error: \(error.localizedDescription)")
                    self.isLoading = false
                }
            }
        }
    }
}
