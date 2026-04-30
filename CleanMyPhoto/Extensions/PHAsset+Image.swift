//
//  PHAsset+Image.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/7.
//

import SwiftUI
import Photos
import UIKit

// MARK: - Image Memory Cache
@MainActor
final class PhotoImageCache {
    static let shared = PhotoImageCache()
    private var cache: [String: UIImage] = [:]

    func get(_ identifier: String) -> UIImage? {
        cache[identifier]
    }

    func set(_ identifier: String, image: UIImage) {
        cache[identifier] = image
    }
}

// MARK: - SwiftUI Image View for PHAsset
struct AssetImage: View {
    let asset: PHAsset
    let targetSize: CGSize
    let contentMode: ContentMode
    var highQuality: Bool = false

    @State private var image: UIImage?

    init(asset: PHAsset, targetSize: CGSize, contentMode: ContentMode = .fit, highQuality: Bool = false) {
        self.asset = asset
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.highQuality = highQuality
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.black
            }
        }
        .onAppear {
            if let cached = PhotoImageCache.shared.get(asset.localIdentifier) {
                image = cached
            }
            loadImage()
        }
        .onChange(of: asset.localIdentifier) { _, newID in
            if let cached = PhotoImageCache.shared.get(newID) {
                image = cached
            }
            loadImage()
        }
    }

    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = highQuality ? .highQualityFormat : .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: self.targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [self] resultImage, info in
            Task { @MainActor in
                if let img = resultImage {
                    self.image = img
                    PhotoImageCache.shared.set(self.asset.localIdentifier, image: img)
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    print("Image loading error: \(error.localizedDescription)")
                }
            }
        }
    }
}
