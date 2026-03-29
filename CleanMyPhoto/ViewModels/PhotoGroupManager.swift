//
//  PhotoGroupManager.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI
import Photos
import Foundation
import Combine

@MainActor
class PhotoGroupManager: NSObject, ObservableObject {
    @Published var yearGroups: [YearGroup] = []
    @Published var isLoading = false
    @Published var scrollToYear: Int? = nil

    let photoManager: PhotoManager

    init(photoManager: PhotoManager) {
        self.photoManager = photoManager
        super.init()
    }

    // 按年月日分组照片
    func groupPhotosByDate() async {
        isLoading = true
        defer { isLoading = false }

        let photos = photoManager.displayedPhotos
        let calendar = Calendar.current

        // 按日期分组
        let grouped = Dictionary(grouping: photos) { photo -> Date in
            // 将日期归一化到当天0点
            let components = calendar.dateComponents([.year, .month, .day], from: photo.asset.creationDate ?? Date())
            return calendar.date(from: components) ?? Date()
        }

        // 构建三级分组结构
        var yearDict: [Int: [Int: [Date: [PhotoAsset]]]] = [:]

        for (date, photos) in grouped {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month else { continue }

            if yearDict[year] == nil {
                yearDict[year] = [:]
            }
            if yearDict[year]?[month] == nil {
                yearDict[year]?[month] = [:]
            }
            yearDict[year]?[month]?[date] = photos
        }

        // 转换为 YearGroup 数组
        let sortedYears = yearDict.keys.sorted(by: >)
        yearGroups = sortedYears.map { year in
            let monthDict = yearDict[year]!
            let sortedMonths = monthDict.keys.sorted(by: >)

            let monthGroups = sortedMonths.map { month in
                let dateDict = monthDict[month]!
                let sortedDates = dateDict.keys.sorted(by: >)

                let dateGroups = sortedDates.map { date in
                    DateGroup(date: date, photos: dateDict[date]!)
                }

                return MonthGroup(
                    year: year,
                    month: month,
                    dateGroups: dateGroups,
                    isExpanded: false
                )
            }

            return YearGroup(
                year: year,
                monthGroups: monthGroups,
                isExpanded: false
            )
        }
    }

    // 展开/折叠年份
    func toggleYear(_ year: Int) {
        if let index = yearGroups.firstIndex(where: { $0.year == year }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                yearGroups[index].isExpanded.toggle()
            }
        }
    }

    // 展开/折叠月份
    func toggleMonth(year: Int, month: Int) {
        if let yearIndex = yearGroups.firstIndex(where: { $0.year == year }),
           let monthIndex = yearGroups[yearIndex].monthGroups.firstIndex(where: { $0.month == month }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                yearGroups[yearIndex].monthGroups[monthIndex].isExpanded.toggle()
            }
        }
    }

    // 获取所有年份列表（用于索引条）
    var years: [Int] {
        yearGroups.map { $0.year }
    }
}
