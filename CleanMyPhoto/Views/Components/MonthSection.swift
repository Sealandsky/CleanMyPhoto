//
//  MonthSection.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI

struct MonthSectionView: View {
    let monthGroup: MonthGroup
    let onPhotoSelect: (PhotoAsset) -> Void
    let onToggleMonth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 月份行
            Button {
                onToggleMonth()
            } label: {
                HStack {
                    Image(systemName: monthGroup.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 32)
                        .animation(.easeInOut(duration: 0.2), value: monthGroup.isExpanded)

                    Text(monthGroup.monthName)
                        .font(.subheadline)
                        .foregroundColor(.white)

                    Spacer()

                    Text("\(monthGroup.totalPhotos)\(String(localized: "photos"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if monthGroup.isExpanded {
                // 日期列表（照片网格）
                ForEach(monthGroup.dateGroups) { dateGroup in
                    DateSectionView(
                        dateGroup: dateGroup,
                        onPhotoSelect: onPhotoSelect
                    )
                }
            }
        }
    }
}
