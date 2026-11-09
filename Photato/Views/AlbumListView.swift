
import SwiftUI
import Photos

struct AlbumListView: View {
    @ObservedObject var albumManager: AlbumManager
    @ObservedObject var onThisDayManager: OnThisDayManager
    @ObservedObject var timelineArchiveManager: TimelineArchiveManager
    @ObservedObject var peopleRecognitionManager: PeopleRecognitionManager = PeopleRecognitionManager.shared
    var organizeManager: PhotoOrganizeManager? = nil
    var onAlbumSelect: ((AlbumModel) -> Void)? = nil
    var onYearGroupSelect: ((OnThisDayYearGroup) -> Void)? = nil
    var onCategorySelect: ((OrganizeCategory) -> Void)? = nil
    var onAllPhotosSelect: (() -> Void)? = nil
    var onMonthArchiveSelect: ((TimelineMonthItem) -> Void)? = nil
    var onAllYearsSelect: (() -> Void)? = nil
    var onPersonSelect: ((PersonEntity) -> Void)? = nil
    var onAllPeopleSelect: (() -> Void)? = nil

    @State private var showNewAlbumAlert = false
    @State private var newAlbumName = ""
    @State private var isCreatingAlbum = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 1. 顶部「往年今日」年份卡片区
                OnThisDaySectionView(manager: onThisDayManager) { group in
                    onYearGroupSelect?(group)
                }

                // 2. 个人相簿分区小标题与新建入口
                albumsSectionHeader

                // 3. 相簿横滑列表（首位常驻「所有照片」卡片）
                if !albumManager.hasLoadedOnce || albumManager.isLoadingAlbums {
                    skeletonRow
                } else {
                    albumsScrollRow
                }

                // 4. 人物与面孔横滑合辑模块
                PeopleAndFacesSectionView(
                    manager: peopleRecognitionManager,
                    onPersonSelect: { person in
                        onPersonSelect?(person)
                    },
                    onViewAllPeople: {
                        onAllPeopleSelect?()
                    }
                )

                // 5. 时光归档模块
                TimelineArchiveSectionView(
                    manager: timelineArchiveManager,
                    onMonthSelect: { item in
                        onMonthArchiveSelect?(item)
                    },
                    onViewAllYears: {
                        onAllYearsSelect?()
                    }
                )

                // 5. 媒体类型板块（从清理页迁移至此）
                mediaTypesSection
            }
        }
        .background(Color.pageBackground)
        .scrollIndicators(.hidden)  // 隐藏滚动条
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .refreshable {
            async let refreshAlbums: () = albumManager.fetchUserAlbums()
            async let refreshOnThisDay: () = onThisDayManager.fetchOnThisDay(forceRefresh: true)
            async let refreshTimeline: () = timelineArchiveManager.loadTimeline(forceRefresh: true)
            async let refreshOrganize: () = {
                if let organizeManager {
                    await organizeManager.quickAnalysis()
                }
            }()
            peopleRecognitionManager.scanPhotoLibrary()
            _ = await (refreshAlbums, refreshOnThisDay, refreshTimeline, refreshOrganize)
        }
        .task {
            if !peopleRecognitionManager.hasScannedOnce && !peopleRecognitionManager.isScanning {
                peopleRecognitionManager.scanPhotoLibrary()
            }
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
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
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

    // MARK: - Albums Horizontal Scroll Row (首位常驻「所有照片」卡片)
    private var albumsScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                // 1. 首位固定卡片：「所有照片」
                AllPhotosCardView(
                    totalCount: albumManager.photoManager.totalPhotoCount
                ) {
                    onAllPhotosSelect?()
                }
                .frame(width: 140, height: 152)

                // 2. 其余用户相册
                ForEach(albumManager.albums) { album in
                    // 堆叠相簿卡片：最多 3 张封面堆叠 + 名称/数量
                    AlbumStackCell(album: album)
                        .frame(width: 140, height: 152)
                        .onTapGesture {
                            onAlbumSelect?(album)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    // MARK: - 媒体类型板块
    private var mediaTypesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 模块大标题：统一 20pt 半粗圆体
            Text(String(localized: "Media Types"))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
                .padding(.top, 16)

            // 纯白浮空分组列表卡
            VStack(spacing: 0) {
                mediaTypeRow(
                    category: .videos,
                    title: String(localized: "Videos"),
                    icon: "video.fill",
                    color: Color(red: 0.38, green: 0.38, blue: 0.94),
                    count: organizeManager?.stat(for: .videos) ?? 0
                )

                Divider()
                    .padding(.leading, 54)

                mediaTypeRow(
                    category: .livePhotos,
                    title: String(localized: "Live Photos"),
                    icon: "livephoto",
                    color: Color(red: 0.96, green: 0.28, blue: 0.58),
                    count: organizeManager?.stat(for: .livePhotos) ?? 0
                )

                Divider()
                    .padding(.leading, 54)

                mediaTypeRow(
                    category: .screenshots,
                    title: String(localized: "Screenshots"),
                    icon: "camera.viewfinder",
                    color: Color(red: 0.04, green: 0.72, blue: 0.82),
                    count: organizeManager?.stat(for: .screenshots) ?? 0
                )
            }
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    // 单行列表项组件
    private func mediaTypeRow(
        category: OrganizeCategory,
        title: String,
        icon: String,
        color: Color,
        count: Int
    ) -> some View {
        Button {
            onCategorySelect?(category)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24, alignment: .center)

                Text(title)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 6) {
                    Text(count.formatted())
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Skeleton Horizontal Row
    private var skeletonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                AllPhotosCardView(
                    totalCount: albumManager.photoManager.totalPhotoCount
                ) {
                    onAllPhotosSelect?()
                }
                .frame(width: 140, height: 152)

                ForEach(0..<3, id: \.self) { _ in
                    AlbumCellSkeleton()
                        .frame(width: 140, height: 152)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
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
        .frame(height: 152)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AlbumStackCell.cardBackgroundColor)
        )
        .shimmering()
    }
}

#Preview {
    AlbumListView(
        albumManager: AlbumManager(photoManager: PhotoManager()),
        onThisDayManager: OnThisDayManager(),
        timelineArchiveManager: TimelineArchiveManager(),
        organizeManager: PhotoOrganizeManager()
    )
}
