//
//  PhotoGroup.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import Foundation

// MARK: - Year Group
struct YearGroup: Identifiable {
    let year: Int
    var monthGroups: [MonthGroup]
    var isExpanded: Bool

    var totalPhotos: Int {
        monthGroups.reduce(0) { $0 + $1.totalPhotos }
    }

    var id: String { "\(year)" }
}

// MARK: - Month Group
struct MonthGroup: Identifiable {
    let year: Int
    let month: Int
    var dateGroups: [DateGroup]
    var isExpanded: Bool

    var totalPhotos: Int {
        dateGroups.reduce(0) { $0 + $1.totalPhotos }
    }

    var id: String { "\(year)-\(month)" }

    var monthName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Locale.current.identifier)
        formatter.dateFormat = "MMMM"
        let date = Calendar.current.date(from: DateComponents(year: year, month: month))!
        return formatter.string(from: date)
    }
}

// MARK: - Date Group
struct DateGroup: Identifiable {
    let date: Date
    let photos: [PhotoAsset]

    var totalPhotos: Int { photos.count }

    var id: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Locale.current.identifier)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var dayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Locale.current.identifier)
        formatter.dateFormat = "d日"
        return formatter.string(from: date)
    }

    var weekdayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Locale.current.identifier)
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}
