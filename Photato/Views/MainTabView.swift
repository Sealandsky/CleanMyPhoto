import SwiftUI

enum AppTab: String, CaseIterable {
    case photos
    case albums
    case organize
    case settings

    var localizedText: String {
        switch self {
        case .photos:
            // 对齐设计稿：底部第一项显示「重温」（该 tab 内顶部分段默认选中发现页）
            return String(localized: "Discover")
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
            return "rectangle.3.group"
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

    // 由本层持有：全屏态驱动底部垃圾桶按钮显隐；回收站 sheet 全局唯一入口
    @State private var isFullscreenMode = false
    @State private var showTrash = false

    // 导航路径：时间线子页在图库内；相簿二级页在本层（相簿已抽离为独立 Tab）
    @State private var timelinePath = NavigationPath()
    @State private var albumsPath = NavigationPath()

    // 「重温」Tab 双击的滚顶信号（递增触发发现页滚回顶部）
    @State private var discoverScrollToTop = 0
    // 上次点击已选中「重温」Tab 的时间，用于双击窗口判定
    @State private var lastDiscoverTapAt: Date?

    // 相簿页状态（复用原相簿组件与数据加载，随相簿 Tab 从图库迁出）
    @State private var albumManager: AlbumManager?
    @State private var selectedAlbum: AlbumModel?
    @State private var albumFullscreenPhotoID: String?   // 相簿照片全屏浏览
    @State private var albumsScrollToPhotoID: String?    // 全屏关闭后列表滚回该照片

    var body: some View {
        GeometryReader { geo in
            // 设备底部安全区高度（Home Indicator 约 34pt；iPad 通常为 0）
            let bottomInset = geo.safeAreaInsets.bottom
            // 底栏视觉下沉量：控件距屏底约 14pt（系统 TabBar 标准位置）
            let sink = max(0, bottomInset - 8)
            tabContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !shouldHideBottomBar {
                        // 底栏：胶囊分段 Tab 组 + 完全独立的圆形回收站按钮
                        // （浮在页面内容之上，不在 TabBar 胶囊内）
                        CapsuleTabBar(
                            segments: AppTab.allCases.map { tab in
                                CapsuleSegment(
                                    id: tab.rawValue,
                                    title: tab.localizedText,
                                    systemImage: tab.systemImage
                                )
                            },
                            selectionID: Binding(
                                get: { selectedTab.rawValue },
                                set: { selectedTab = AppTab(rawValue: $0) ?? selectedTab }
                            ),
                            accessorySystemImage: "trash",
                            // iOS 26+ 启用 Liquid Glass 背景；iOS 18 自动回退 systemBackground
                            prefersLiquidGlass: true,
                            // 双击已选中的「重温」Tab：滚回发现页最顶部
                            // （单击不再触发；两次点击间隔 0.35s 内视为双击）
                            onReselect: { id in
                                guard id == AppTab.photos.rawValue else { return }
                                let now = Date()
                                if let last = lastDiscoverTapAt,
                                   now.timeIntervalSince(last) < 0.35 {
                                    lastDiscoverTapAt = nil
                                    discoverScrollToTop += 1
                                } else {
                                    lastDiscoverTapAt = now
                                }
                            },
                            onAccessoryTap: { showTrash = true }
                        )
                        // 下沉到系统 TabBar 的标准位置
                        .offset(y: sink)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: shouldHideBottomBar)
                .sheet(isPresented: $showTrash) {
                    TrashView(photoManager: photoManager)
                        // 默认半屏（medium）呈现，用户上滑展开为全屏（large）
                        .presentationDetents([.medium, .large])
                }
                .tint(.white)
        }
    }

    // MARK: - Tab Pages
    // 系统 TabBar 永久隐藏（其胶囊无法只占左侧宽度），底部栏由 CapsuleTabBar 自绘接管
    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            ContentView(
                isFullscreenMode: $isFullscreenMode,
                showTrash: $showTrash,
                timelinePath: $timelinePath,
                discoverScrollToTop: $discoverScrollToTop
            )
            .toolbar(.hidden, for: .tabBar)
            .tag(AppTab.photos)

            albumsTabContent
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.albums)

            organizeTabContent
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.organize)

            SettingsView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.settings)
        }
    }

    // MARK: - Albums Tab
    /// 相簿：从图库内子页抽离为独立底部 Tab。
    /// 相簿列表/照片列表组件、数据加载、排序与跳转逻辑沿用原有实现，
    /// 照片点击后在 Tab 内叠加全屏浏览器（FullscreenPhotoBrowser 共享组件）。
    private var albumsTabContent: some View {
        ZStack {
            NavigationStack(path: $albumsPath) {
                Group {
                    if let albumMgr = albumManager {
                        AlbumListView(albumManager: albumMgr) { album in
                            selectedAlbum = album
                            Task { [album] in
                                await albumMgr.fetchPhotos(in: album)
                                guard selectedAlbum?.id == album.id else { return }
                                albumsPath.append(AlbumsDestination.albumPhotos(album.id))
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
                    case .albumPhotos(let albumId):
                        if let album = albumManager?.albums.first(where: { $0.id == albumId }),
                           let albumMgr = albumManager {
                            AlbumPhotoListView(
                                albumManager: albumMgr,
                                photoManager: photoManager,
                                album: album,
                                onPhotoSelect: { photo in
                                    // 点击照片：在本 Tab 内打开共享全屏浏览器
                                    albumFullscreenPhotoID = photo.id
                                },
                                scrollToPhotoID: albumsScrollToPhotoID
                            )
                        }
                    }
                }
            }

            // 相簿照片全屏浏览层：交互与图库全屏完全一致（共享组件）
            if let albumMgr = albumManager, let photoID = albumFullscreenPhotoID {
                FullscreenPhotoBrowser(
                    photos: albumMgr.displayedAlbumPhotos,
                    initialPhotoID: photoID,
                    onDelete: { photo in
                        // 删除经 photoManager 落回收站；列表随 displayedAlbumPhotos 自动收缩
                        photoManager.addToTrash(photo)
                    },
                    onDismiss: {
                        // 关闭后列表滚动定位到刚浏览的照片
                        albumsScrollToPhotoID = albumFullscreenPhotoID
                        albumFullscreenPhotoID = nil
                    }
                )
                .transition(.opacity)
            }
        }
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
    }

    // MARK: - Loading View（相簿管理器初始化中的占位）
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text(String(localized: "Loading photos..."))
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
    }

    // MARK: - Bottom Bar Visibility
    /// 对齐原系统 TabBar 行为：全屏浏览、滑动多选、任一二级页（相簿列表 push /
    /// 时间线月视图 / 整理结果）中隐藏底部栏
    private var shouldHideBottomBar: Bool {
        isFullscreenMode ||
        albumFullscreenPhotoID != nil ||
        photoManager.isSelectMode ||
        !albumsPath.isEmpty ||
        !timelinePath.isEmpty ||
        !organizePath.isEmpty
    }
}

#Preview {
    MainTabView()
        .environmentObject(PhotoManager())
        .environmentObject(MembershipManager())
        .environmentObject(StatisticsManager())
        .environment(GridSettings())
}
