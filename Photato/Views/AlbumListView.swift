
import SwiftUI
import Photos

struct AlbumListView: View {
    @ObservedObject var albumManager: AlbumManager
    @ObservedObject var onThisDayManager: OnThisDayManager
    let onAlbumSelect: (AlbumModel) -> Void
    var onYearGroupSelect: ((OnThisDayYearGroup) -> Void)? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 1. 顶部「过去的今天」年份卡片区
                OnThisDaySectionView(manager: onThisDayManager) { group in
                    onYearGroupSelect?(group)
                }

                // 2. 相簿网格内容
                if albumManager.isLoadingAlbums {
                    skeletonGrid
                } else if albumManager.albums.isEmpty {
                    emptyAlbumsView
                } else {
                    albumsGrid
                }
            }
        }
        .background(Color.pageBackground)
        .scrollIndicators(.hidden)  // 隐藏滚动条
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .refreshable {
            async let refreshAlbums: () = albumManager.fetchUserAlbums()
            async let refreshOnThisDay: () = onThisDayManager.fetchOnThisDay(forceRefresh: true)
            _ = await (refreshAlbums, refreshOnThisDay)
        }
    }

    // MARK: - Albums Grid
    private var albumsGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(albumManager.albums) { album in
                // 堆叠相簿卡片：最多 3 张封面堆叠 + 名称/数量
                AlbumStackCell(album: album)
                    .onTapGesture {
                        onAlbumSelect(album)
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    // MARK: - Skeleton Grid
    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<6, id: \.self) { _ in
                AlbumCellSkeleton()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 24)
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
        .frame(maxWidth: .infinity)
        .frame(minHeight: UIScreen.main.bounds.height * 0.7)
    }
}

// MARK: - Album Cell Skeleton
struct AlbumCellSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gray.opacity(0.18))
                .frame(width: 80, height: 80)
            Spacer(minLength: 8)
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 14)
                    .padding(.horizontal, 24)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 12)
                    .padding(.horizontal, 44)
            }
            Spacer().frame(height: 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AlbumStackCell.cardBackgroundColor)
        )
        .shimmering()
    }
}

#Preview {
    AlbumListView(
        albumManager: AlbumManager(photoManager: PhotoManager()),
        onThisDayManager: OnThisDayManager()
    ) { _ in }
}
