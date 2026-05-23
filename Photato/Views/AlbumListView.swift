
import SwiftUI

struct AlbumListView: View {
    @ObservedObject var albumManager: AlbumManager
    let onAlbumSelect: (AlbumModel) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            if albumManager.isLoadingAlbums {
                skeletonGrid
            } else if albumManager.albums.isEmpty {
                emptyAlbumsView
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(albumManager.albums) { album in
                        AlbumCell(album: album)
                            .onTapGesture {
                                onAlbumSelect(album)
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color.black)
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
                .foregroundColor(.white)

            Text(String(localized: "You haven't created any albums yet."))
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Album Cell Skeleton
struct AlbumCellSkeleton: View {
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shimmering()
    }
}

#Preview {
    AlbumListView(albumManager: AlbumManager(photoManager: PhotoManager())) { _ in }
}
