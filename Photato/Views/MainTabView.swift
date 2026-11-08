import SwiftUI
import StoreKit
import Photos

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
    /// 统计埋点用的英文界面名（只记录界面名，不记录内容）。
    var analyticsName: String {
        switch self {
        case .photos:
            return "Memories"
        case .albums:
            return "Albums"
        case .organize:
            return "Organize"
        case .settings:
            return "Settings"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var membershipManager: MembershipManager
    @EnvironmentObject var statisticsManager: StatisticsManager
    @Environment(\.requestReview) private var requestReview

    @State private var selectedTab: AppTab = .photos
    @State private var organizeManager = PhotoOrganizeManager()
    @State private var organizePath = NavigationPath()

    // 由本层持有：全屏态同步
    @State private var isFullscreenMode = false

    // 导航路径：相簿二级页在本层（相簿已抽离为独立 Tab）
    @State private var albumsPath = NavigationPath()

    // 相簿页状态（复用原相簿组件与数据加载，随相簿 Tab 从图库迁出）
    @StateObject private var onThisDayManager = OnThisDayManager()
    @StateObject private var timelineArchiveManager = TimelineArchiveManager()
    @State private var albumManager: AlbumManager?
    @State private var selectedAlbum: AlbumModel?

    init() {
        Self.configureTabBarAppearance()
        UITabBarItem.swizzleItemSettersOnce()
        UITabBar.swizzleLayoutSubviewsOnce()
    }

    static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let unselectedColor = UIColor.systemGray // #8E8E93 中灰
        let selectedColor = UIColor.label        // 浅色纯黑 #000000，深色纯白 #FFFFFF

        for layout in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ] {
            layout.normal.iconColor = unselectedColor
            layout.normal.titleTextAttributes = [
                .foregroundColor: unselectedColor,
                .font: UIFont.systemFont(ofSize: 10, weight: .regular)
            ]
            layout.selected.iconColor = selectedColor
            layout.selected.titleTextAttributes = [
                .foregroundColor: selectedColor,
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
            ]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = selectedColor
        UITabBar.appearance().unselectedItemTintColor = unselectedColor
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(
                isFullscreenMode: $isFullscreenMode
            )
            .tint(Color.accentColor)
            .toolbar(isFullscreenMode ? .hidden : .visible, for: .tabBar)
            .tabItem {
                Label(AppTab.photos.localizedText, systemImage: AppTab.photos.systemImage)
            }
            .tag(AppTab.photos)

            albumsTabContent
                .tint(Color.accentColor)
                .tabItem {
                    Label(AppTab.albums.localizedText, systemImage: AppTab.albums.systemImage)
                }
                .tag(AppTab.albums)

            organizeTabContent
                .tint(Color.accentColor)
                .tabItem {
                    Label(AppTab.organize.localizedText, systemImage: AppTab.organize.systemImage)
                }
                .tag(AppTab.organize)

            SettingsView(
                onNavigateToOrganize: {
                    selectedTab = .organize
                }
            )
            .environment(organizeManager)
            .tint(Color.accentColor)
            .tabItem {
                Label(AppTab.settings.localizedText, systemImage: AppTab.settings.systemImage)
            }
            .tag(AppTab.settings)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .onChange(of: selectedTab) { _, newTab in
            AppAnalytics.screen(newTab.analyticsName)
        }
        .task {
            AppAnalytics.screen(selectedTab.analyticsName)
            // 1. 首屏渲染完成即刻轻量预热特征内存库（~20ms），确保用户点进详情页秒出相似照片
            try? await Task.sleep(nanoseconds: 150_000_000)
            PhotoSimilarityMatcher.shared.prewarm()

            // 2. 预热「过去的今天」与相册列表，确保用户切到相册 Tab 时秒出、零跳变
            Task(priority: .userInitiated) {
                if !onThisDayManager.hasLoadedOnce {
                    await onThisDayManager.fetchOnThisDay()
                }
            }

            // 3. 待首屏交互彻底稳定后（2s），后台低优先级预热整理页快速缓存
            try? await Task.sleep(nanoseconds: 1_850_000_000)
            Task(priority: .utility) {
                await organizeManager.quickAnalysis()
            }

            // 4. 梯次延迟（3s）启动后台全相册 AI 特征静默建库，零卡顿、不抢占前台算力
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            PhotoSimilarityMatcher.shared.startBackgroundIndexingIfNeeded()
        }
        .sheet(isPresented: $photoManager.showTrash, onDismiss: {
            if let pending = photoManager.pendingCleanupResult {
                photoManager.pendingCleanupResult = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    photoManager.lastCleanupResult = pending
                }
            }
        }) {
            TrashView(photoManager: photoManager)
                // 默认半屏（medium）呈现，用户上滑展开为全屏（large）
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $photoManager.lastCleanupResult) { result in
            CleanupResultView(result: result) {
                photoManager.lastCleanupResult = nil
                ReviewPromptManager.shared.requestReviewIfAppropriate(deletedCount: result.deletedCount, requestReview: requestReview)
            }
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
                    AlbumListView(
                        albumManager: albumMgr,
                        onThisDayManager: onThisDayManager,
                        timelineArchiveManager: timelineArchiveManager,
                        organizeManager: organizeManager,
                        onAlbumSelect: { album in
                            selectedAlbum = album
                            Task { [album] in
                                await albumMgr.fetchPhotos(in: album)
                                guard selectedAlbum?.id == album.id else { return }
                                albumsPath.append(AlbumsDestination.albumDetail(album.id))
                            }
                        },
                        onYearGroupSelect: { group in
                            albumsPath.append(AlbumsDestination.onThisDay(group))
                        },
                        onCategorySelect: { category in
                            albumsPath.append(AlbumsDestination.categoryResults(category))
                        },
                        onAllPhotosSelect: {
                            albumsPath.append(AlbumsDestination.allPhotos)
                        },
                        onMonthArchiveSelect: { item in
                            albumsPath.append(AlbumsDestination.monthArchive(item))
                        },
                        onAllYearsSelect: {
                            albumsPath.append(AlbumsDestination.allYearsArchive)
                        }
                    )
                } else {
                    loadingView
                }
            }
            .tabInlineNavigationTitle(String(localized: "Albums")) {
                PendingPhotosEntryButton(isLiquidGlass: true)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .task {
                // 首次进入相簿 Tab 时创建管理器（TabView 懒加载，未选中该 Tab
                // 前不会执行）；每次进入都静默刷新相簿列表——详情页「添加到相簿/
                // 新建相簿」不经过本管理器写入，靠此处保证计数与列表最新
                if albumManager == nil {
                    albumManager = AlbumManager(photoManager: photoManager)
                }
                guard let albumMgr = albumManager else { return }

                // 并行并发拉取，互不等待阻塞
                if !onThisDayManager.hasLoadedOnce {
                    Task { await onThisDayManager.fetchOnThisDay() }
                }
                if !timelineArchiveManager.hasLoadedOnce {
                    Task { await timelineArchiveManager.loadTimeline() }
                }
                if organizeManager.stat(for: .videos) == 0 && !organizeManager.isAnalyzing {
                    Task { await organizeManager.quickAnalysis() }
                }
                await albumMgr.fetchUserAlbums()
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
                case .onThisDay(let group):
                    OnThisDayPhotoListView(
                        group: group,
                        photoManager: photoManager
                    )
                case .categoryResults(let category):
                    OrganizeResultsView(
                        organizeManager: organizeManager,
                        category: category,
                        photoManager: photoManager
                    )
                case .allPhotos:
                    PhotoStreamView(
                        streamTitle: String(localized: "All Photos"),
                        fetchPhotos: {
                            await Task.detached(priority: .userInitiated) {
                                let options = PHFetchOptions()
                                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                                options.predicate = NSPredicate(format: "isHidden == false")
                                let result = PHAsset.fetchAssets(with: options)
                                var list: [PhotoAsset] = []
                                result.enumerateObjects { asset, _, _ in
                                    list.append(PhotoAsset(asset: asset))
                                }
                                return list
                            }.value
                        },
                        photoManager: photoManager
                    )
                case .monthArchive(let item):
                    PhotoStreamView(
                        streamTitle: "\(item.yearTitle) · \(item.monthName)",
                        fetchPhotos: {
                            await Task.detached(priority: .userInitiated) {
                                let options = PHFetchOptions()
                                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                                options.predicate = NSPredicate(
                                    format: "creationDate >= %@ AND creationDate < %@ AND isHidden == false",
                                    item.startDate as NSDate,
                                    item.endDate as NSDate
                                )
                                let result = PHAsset.fetchAssets(with: options)
                                var list: [PhotoAsset] = []
                                result.enumerateObjects { asset, _, _ in
                                    list.append(PhotoAsset(asset: asset))
                                }
                                return list
                            }.value
                        },
                        photoManager: photoManager
                    )
                case .allYearsArchive:
                    AllYearsArchiveView(
                        manager: timelineArchiveManager,
                        onMonthSelect: { item in
                            albumsPath.append(AlbumsDestination.monthArchive(item))
                        }
                    )
                }
            }
        }
        .background(Color.pageBackground)
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
            .tabInlineNavigationTitle(String(localized: "Organize")) {
                PendingPhotosEntryButton(isLiquidGlass: true)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
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
        .background(Color.pageBackground)
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
        .background(Color.pageBackground)
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

// MARK: - Native TabBar Item Appearance Swizzling
extension UITabBarItem {
    private static var hasSwizzledItem = false

    static func swizzleItemSettersOnce() {
        guard !hasSwizzledItem else { return }
        hasSwizzledItem = true

        let origSel = #selector(setter: UITabBarItem.image)
        let swizSel = #selector(photato_setImage(_:))

        if let orig = class_getInstanceMethod(UITabBarItem.self, origSel),
           let swiz = class_getInstanceMethod(UITabBarItem.self, swizSel) {
            method_exchangeImplementations(orig, swiz)
        }
    }

    @objc private func photato_setImage(_ image: UIImage?) {
        guard let image else {
            photato_setImage(nil)
            return
        }

        if image.renderingMode == .alwaysOriginal {
            photato_setImage(image)
            return
        }

        let unselectedColor = UIColor.systemGray
        let selectedColor = UIColor.label

        let grayImage = image.withTintColor(unselectedColor, renderingMode: .alwaysOriginal)
        let blackImage = image.withTintColor(selectedColor, renderingMode: .alwaysOriginal)

        photato_setImage(grayImage)
        self.selectedImage = blackImage

        setTitleTextAttributes([
            .foregroundColor: unselectedColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .regular)
        ], for: .normal)
        setTitleTextAttributes([
            .foregroundColor: selectedColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ], for: .selected)
    }
}

extension UITabBar {
    private static var hasSwizzled = false

    static func swizzleLayoutSubviewsOnce() {
        guard !hasSwizzled else { return }
        hasSwizzled = true

        let originalSelector = #selector(layoutSubviews)
        let swizzledSelector = #selector(photato_layoutSubviews)

        guard let originalMethod = class_getInstanceMethod(UITabBar.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UITabBar.self, swizzledSelector) else { return }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    @objc func photato_layoutSubviews() {
        photato_layoutSubviews()

        guard let items = self.items else { return }
        let unselectedColor = UIColor.systemGray
        let selectedColor = UIColor.label

        for item in items {
            if let base = item.image, base.renderingMode != .alwaysOriginal {
                let gray = base.withTintColor(unselectedColor, renderingMode: .alwaysOriginal)
                let black = base.withTintColor(selectedColor, renderingMode: .alwaysOriginal)
                item.image = gray
                item.selectedImage = black
                item.setTitleTextAttributes([
                    .foregroundColor: unselectedColor,
                    .font: UIFont.systemFont(ofSize: 10, weight: .regular)
                ], for: .normal)
                item.setTitleTextAttributes([
                    .foregroundColor: selectedColor,
                    .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
                ], for: .selected)
            }
        }
    }
}

