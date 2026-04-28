//
//  SystemAlbumCollection.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import Foundation
import Photos
import UIKit

/// 系统年份相册
struct YearAlbum: Identifiable {
    let collection: PHAssetCollection?
    let fetchResult: PHFetchResult<PHAsset>?
    let assets: [PHAsset]
    let year: Int
    var thumbnail: UIImage?

    var id: String {
        if let collection = collection {
            return collection.localIdentifier
        } else {
            return "year_\(year)"
        }
    }

    var photoCount: Int {
        if let fetchResult = fetchResult {
            return fetchResult.count
        }
        return assets.count
    }

    var yearName: String {
        "\(year)"
    }
}

/// 系统月份相册
struct MonthAlbum: Identifiable {
    let collection: PHAssetCollection?
    let fetchResult: PHFetchResult<PHAsset>?
    let assets: [PHAsset]
    let year: Int
    let month: Int
    var thumbnail: UIImage?

    var id: String {
        if let collection = collection {
            return collection.localIdentifier
        } else {
            return "month_\(year)_\(month)"
        }
    }

    var photoCount: Int {
        if let fetchResult = fetchResult {
            return fetchResult.count
        }
        return assets.count
    }

    var monthName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Locale.current.identifier)
        formatter.dateFormat = "MMMM"
        let date = Calendar.current.date(from: DateComponents(year: year, month: month))!
        return formatter.string(from: date)
    }

    var fullTitle: String {
        "\(year) " + monthName
    }

    var photoAssets: [PhotoAsset] {
        if let fetchResult {
            return (0..<fetchResult.count).compactMap { index in
                guard index < fetchResult.count else { return nil }
                return PhotoAsset(asset: fetchResult.object(at: index))
            }
        }
        return assets.map { PhotoAsset(asset: $0) }
    }
}
