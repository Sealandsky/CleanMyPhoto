
import SwiftUI
import Photos

struct AlbumListView: View {
    @ObservedObject var albumManager: AlbumManager
    @ObservedObject var onThisDayManager: OnThisDayManager
    let onAlbumSelect: (AlbumModel) -> Void
    var onYearGroupSelect: ((OnThisDayYearGroup) -> Void)? = nil

    @State private var showNewAlbumAlert = false
    @State private var newAlbumName = ""
    @State private var isCreatingAlbum = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 1. 顶部「过去的今天」年份卡片区
                OnThisDaySectionView(manager: onThisDayManager) { group in
                    onYearGroupSelect?(group)
                }

                // 2. 个人相簿分区小标题与新建入口
                albumsSectionHeader

                // 3. 相簿网格内容
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
        .alert(String(localized: "New Album"), isPresented: $showNewAlbumAlert) {
            TextField(String(localized: "Album Name"), text: $newAlbumName)
                .textInputAutocapitalization(.words)

            Button(String(localized: "Create")) {
                createNewAlbum()
            }
            .disabled(newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(String(localized: "Cancel"), role: .cancel) {
                newAlbumName = ""
            }
        } message: {
            Text(String(localized: "Enter a name for this album."))
        }
        .alert(String(localized: "Failed to create album"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Section Header
    private var albumsSectionHeader: some View {
        HStack(alignment: .center) {
            Text(String(localized: "My Albums"))
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(Color(.secondaryLabel))
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                SoundManager.playAction()
                newAlbumName = ""
                showNewAlbumAlert = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                    Text(String(localized: "New Album"))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundColor(.accentColor)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "New Album"))
            .accessibilityAddTraits(.isButton)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func createNewAlbum() {
        let title = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreatingAlbum else { return }
        isCreatingAlbum = true
        Task {
            do {
                _ = try await albumManager.createAlbum(title: title)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                AppAnalytics.event("album_created")
                isCreatingAlbum = false
                newAlbumName = ""
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                isCreatingAlbum = false
                errorMessage = error.localizedDescription
            }
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
        .padding(.vertical, 60)
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
