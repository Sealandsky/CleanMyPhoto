
import SwiftUI
import Photos

struct DateSectionView: View {
    let dateGroup: DateGroup
    let onPhotoSelect: (PhotoAsset) -> Void
    @Environment(GridSettings.self) private var gridSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 日期标题
            HStack {
                Text(dateGroup.dayText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.leading, 48)

                Text(dateGroup.weekdayText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(dateGroup.totalPhotos)\(String(localized: "photos"))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            // 照片网格
            LazyVGrid(columns: GridColumnHelper.columns(count: gridSettings.columnCount), spacing: GridColumnHelper.spacing) {
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
