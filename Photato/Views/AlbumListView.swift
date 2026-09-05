
import SwiftUI
import Photos

struct AlbumListView: View {
    @ObservedObject var albumManager: AlbumManager
    let onAlbumSelect: (AlbumModel) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    var body: some View {
        ScrollView {
            if albumManager.isLoadingAlbums {
                skeletonGrid
            } else if albumManager.albums.isEmpty {
                emptyAlbumsView
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(albumManager.albums) { album in
                        // 堆叠相簿卡片：最多 3 张封面堆叠 + 名称/数量
                        AlbumStackCell(album: album)
                            .onTapGesture {
                                onAlbumSelect(album)
                            }
                    }
                }
                .padding(.horizontal, 12)
                // 尾部高度占位：滚动到底时最后一行不被悬浮底栏遮挡
                .padding(.bottom, 90)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .scrollIndicators(.hidden)  // 隐藏滚动条
    }

    // MARK: - Skeleton Grid
    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                AlbumCellSkeleton()
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    private var emptyAlbumsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60, design: .rounded))
                .foregroundColor(.gray)

            Text(String(localized: "No Albums Found"))
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text(String(localized: "You haven't created any albums yet."))
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Album Cell Skeleton
struct AlbumCellSkeleton: View {
    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
            VStack(spacing: 4) {
                Rectangle().fill(Color.gray.opacity(0.3))
                    .frame(height: 12)
                    .padding(.horizontal, 24)
                Rectangle().fill(Color.gray.opacity(0.2))
                    .frame(height: 10)
                    .padding(.horizontal, 40)
            }
        }
        .shimmering()
    }
}

#Preview {
    AlbumListView(albumManager: AlbumManager(photoManager: PhotoManager())) { _ in }
}
