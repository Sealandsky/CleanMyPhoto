//
//  YearSection.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI

struct YearSectionView: View {
    let yearGroup: YearGroup
    let onPhotoSelect: (PhotoAsset) -> Void
    let onToggleYear: () -> Void
    let onToggleMonth: (Int, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 年份行
            Button {
                onToggleYear()
            } label: {
                HStack {
                    Image(systemName: yearGroup.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.2), value: yearGroup.isExpanded)

                    Text("\(yearGroup.year)")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Text("\(yearGroup.totalPhotos)\(String(localized: "photos"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if yearGroup.isExpanded {
                // 月份列表
                ForEach(yearGroup.monthGroups) { monthGroup in
                    MonthSection(
                        monthGroup: monthGroup,
                        onPhotoSelect: onPhotoSelect,
                        onToggleMonth: {
                            onToggleMonth(monthGroup.year, monthGroup.month)
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Month Section (standalone component for preview)
struct MonthSection: View {
    let monthGroup: MonthGroup
    let onPhotoSelect: (PhotoAsset) -> Void
    let onToggleMonth: () -> Void

    var body: some View {
        MonthSectionView(
            monthGroup: monthGroup,
            onPhotoSelect: onPhotoSelect,
            onToggleMonth: onToggleMonth
        )
    }
}
