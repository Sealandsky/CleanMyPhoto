//
//  DateSection.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI

struct DateSectionView: View {
    let dateGroup: DateGroup
    let onPhotoSelect: (PhotoAsset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 日期标题
            HStack {
                Text(dateGroup.dayText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 48)

                Text(dateGroup.weekdayText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(dateGroup.totalPhotos)\(String(localized: "photos"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            // 照片网格
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(dateGroup.photos) { photo in
                    PhotoCell(photo: photo)
                        .onTapGesture {
                            onPhotoSelect(photo)
                        }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 16)
    }
}
