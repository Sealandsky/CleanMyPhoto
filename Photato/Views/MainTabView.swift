import SwiftUI

enum AppTab: String, CaseIterable {
    case photos
    case albums
    case organize
    case settings

    var localizedText: String {
        switch self {
        case .photos:
            // 底部第一项显示「回忆」
            return String(localized: "Memories")
        case .albums:
            return String(localized: "Albums")
        case .organize:
            return String(localized: "Organize")
        case .settings:
            return String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .photos:
            return "rectangle.3.group.fill"
        case .albums:
            return "photo.on.rectangle.angled"
        case .organize:
            // sparkles.2 为 SF Symbols 7 符号（iOS 26+ 可用）；
            // iOS 18 设备回退 sparkles，避免渲染空白
            if #available(iOS 26.0, *) {
                return "sparkles.2"
            }
            return "sparkles"
        case .settings:
            // 底部 TabBar 设置入口使用实心齿轮图标
            return "gearshape.fill"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var membershipManager: MembershipManager
    @EnvironmentObject var statisticsManager: StatisticsManager

    @State private var selectedTab: AppTab = .photos
    @State private var organizeManager = PhotoOrganizeManager()
    @State private var organizePath = NavigationPath()

    // 由本层持有：全屏态同步
    @State private var isFullscreenMode = false

    // 导航路径：相簿二级页在本层（相簿已抽离为独立 Tab）
    @State private var albumsPath = NavigationPath()

    // 相簿页状态（复用原相簿组件与数据加载，随相簿 Tab 从图库迁出）
    @State private var albumManager: AlbumManager?
    @State private var selectedAlbum: AlbumModel?

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(
                isFullscreenMode: $isFullscreenMode
            )
            .tabItem {
                Label(AppTab.photos.localizedText, systemImage: AppTab.photos.systemImage)
            }
            .tag(AppTab.photos)

            albumsTabContent
                .tabItem {
                    Label(AppTab.albums.localizedText, systemImage: AppTab.albums.systemImage)
                }
                .tag(AppTab.albums)

            organizeTabContent
                .tabItem {
                    Label(AppTab.organize.localizedText, systemImage: AppTab.organize.systemImage)
                }
                .tag(AppTab.organize)

            SettingsView()
                .tabItem {
                    Label(AppTab.settings.localizedText, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)
        }
        .task {
            // 启动预热：提前把相似照片特征库载入内存，
            // 详情页初始化的同步快照即为纯内存查询（与首帧同在）
            PhotoSimilarityMatcher.shared.prewarm()

            // 后台低优先级预热整理页快速缓存，避免首次切 Tab 时等待
            Task(priority: .utility) {
                await organizeManager.quickAnalysis()
            }
        }
        .sheet(isPresented: $photoManager.showTrash) {
            TrashView(photoManager: photoManager)
                // 默认半屏（medium）呈现，用户上滑展开为全屏（large）
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Albums Tab
    /// 相簿：从图库内子页抽离为独立底部 Tab。
    /// 相簿列表/照片列表组件、数据加载、排序与跳转逻辑沿用原有实现，
    /// 照片点击后在 Tab 内叠加全屏浏览器（FullscreenPhotoBrowser 共享组件）。
    private var albumsTabContent: some View {
        NavigationStack(path: $albumsPath) {
            Group {
                if let albumMgr = albumManager {
                    AlbumListView(albumManager: albumMgr) { album in
                        selectedAlbum = album
                        Task { [album] in
                            await albumMgr.fetchPhotos(in: album)
                            guard selectedAlbum?.id == album.id else { return }
                            albumsPath.append(AlbumsDestination.albumDetail(album.id))
                        }
                    }
                } else {
                    loadingView
                }
            }
            .navigationTitle(String(localized: "Albums"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(alignment: .top) {
                TopBlurFadeBackground(height: 200)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        photoManager.showTrash = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .task {
                // 首次进入相簿 Tab 时创建管理器并拉取相簿列表（TabView 懒加载，
                // 未选中该 Tab 前不会执行）
                if albumManager == nil {
                    albumManager = AlbumManager(photoManager: photoManager)
                }
                if let albumMgr = albumManager, albumMgr.albums.isEmpty {
                    await albumMgr.fetchUserAlbums()
                }
            }
            .navigationDestination(for: AlbumsDestination.self) { destination in
                switch destination {
                case .albumDetail(let albumId):
                    if let album = albumManager?.albums.first(where: { $0.id == albumId }),
                       let albumMgr = albumManager {
                        AlbumDetailView(
                            albumManager: albumMgr,
                            photoManager: photoManager,
                            album: album,
                            onViewAllTapped: {
                                albumsPath.append(AlbumsDestination.albumAllPhotos(album.id))
                            }
                        )
                    }
                case .albumAllPhotos(let albumId):
                    if let album = albumManager?.albums.first(where: { $0.id == albumId }),
                       let albumMgr = albumManager {
                        AlbumPhotoListView(
                            albumManager: albumMgr,
                            photoManager: photoManager,
                            album: album,
                            onPhotoSelect: { _ in }
                        )
                    }
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Organize Tab
    private var organizeTabContent: some View {
        NavigationStack(path: $organizePath) {
            OrganizeView(
                organizeManager: organizeManager,
                photoManager: photoManager,
                onCategorySelect: { category in
                    organizePath.append(OrganizeDestination.categoryResults(category))
                }
            )
            .navigationTitle(String(localized: "Organize"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(alignment: .top) {
                TopBlurFadeBackground(height: 200)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        photoManager.showTrash = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .navigationDestination(for: OrganizeDestination.self) { destination in
                switch destination {
                case .categoryResults(let category):
                    OrganizeResultsView(
                        organizeManager: organizeManager,
                        category: category,
                        photoManager: photoManager
                    )
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Loading View（相簿管理器初始化中的占位）
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.primary)

            Text(String(localized: "Loading photos..."))
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .ignoresSafeArea()
    }
}

#Preview {
    MainTabView()
        .environmentObject(PhotoManager())
        .environmentObject(MembershipManager())
        .environmentObject(StatisticsManager())
        .environment(GridSettings())
}
