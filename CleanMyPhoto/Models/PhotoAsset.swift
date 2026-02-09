//
//  PhotoAsset.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/9.
//

import Foundation
import Photos

// MARK: - Photo Asset Model
struct PhotoAsset: Identifiable, Equatable {
    let id: String
    let asset: PHAsset

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
    }

    static func == (lhs: PhotoAsset, rhs: PhotoAsset) -> Bool {
        lhs.id == rhs.id
    }
}
