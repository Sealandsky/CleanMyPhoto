//
//  PhotoSection.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/9.
//

import Foundation

// MARK: - Photo Section Model
struct PhotoSection: Identifiable {
    let id = UUID()
    let month: String
    let year: Int
    let photos: [PhotoAsset]

    var displayTitle: String {
        return month + " " + String(year)
    }
}
