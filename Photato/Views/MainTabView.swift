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
    @Environment(\.scenePhase) private var scenePhase

    /// widget deep link 待消费年份（-1 表示仅切 Tab 不带年份）
    @Binding var pendingDeepLinkYear: Int?

    /// 底部 tab 图标尺寸：系统默认约 24pt，缩小一档到 20pt。改这一个常量即可全 tab 生效。
    private let tabIconSize: CGFloat = 20

    @State private var selectedTab: AppTab = {
        #if DEBUG
        if CommandLine.arguments.contains("-tab_albums") { return .albums }
        if CommandLine.arguments.contains("-tab_organize") { return .organize }
        if CommandLine.arguments.contains("-tab_settings") { return .settings }
        #endif
        return .photos
    }()
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

    init(pendingDeepLinkYear: Binding<Int?>) {
        self._pendingDeepLinkYear = pendingDeepLinkYear
        Self.configureTabBarAppearance()
        // iOS 26 液态玻璃修复（Bryan 真机反馈：按住 tab 无液态玻璃形变）：
        // 原先用 swizzle 把 item.image 强制替换为 .alwaysOriginal 位图，
        // 这会让 tab 项退出系统的液态玻璃渲染，且每次 layoutSubviews 重设
        // 图片会打断按住时的形变状态。现在只用标准 appearance 着色。
    }

    static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let unselectedColor = UITabBar.unselectedTabColor
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
                Label {
                    Text(AppTab.photos.localizedText)
                } icon: {
                    Image(systemName: AppTab.photos.systemImage)
                        .font(.system(size: tabIconSize, weight: .medium))
                }
            }
            .tag(AppTab.photos)

            albumsTabContent
                .tint(Color.accentColor)
                .tabItem {
                    Label {
                        Text(AppTab.albums.localizedText)
                    } icon: {
                        Image(systemName: AppTab.albums.systemImage)
                            .font(.system(size: tabIconSize, weight: .medium))
                    }
                }
                .tag(AppTab.albums)

            organizeTabContent
                .tint(Color.accentColor)
                .tabItem {
                    Label {
                        Text(AppTab.organize.localizedText)
                    } icon: {
                        Image(systemName: AppTab.organize.systemImage)
                            .font(.system(size: tabIconSize, weight: .medium))
                    }
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
                Label {
                    Text(AppTab.settings.localizedText)
                } icon: {
                    Image(systemName: AppTab.settings.systemImage)
                        .font(.system(size: tabIconSize, weight: .medium))
                }
            }
            .tag(AppTab.settings)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .modifier(DefaultTabBarPlacementModifier())
        .onChange(of: selectedTab) { _, newTab in
            AppAnalytics.screen(newTab.analyticsName)
        }
        .onChange(of: pendingDeepLinkYear) { _, year in
            guard let year else { return }
            Task { await resolveAndNavigateIfNeeded(year: year) }
        }
        .onChange(of: scenePhase) { _, phase in
            // 进入后台再写一次快照，补齐未回填的地名 / 当天变更，并向系统预约夜间静默刷新
            if phase == .background {
                Task { await writeWidgetSnapshot(force: false) }
                OnThisDayBackgroundScheduler.shared.scheduleNextRefresh()
            }
        }
        .task {
            // widget 快照写入钩子：manager 数据（含地名回填）变化时重建
            onThisDayManager.onDataChanged = { [weak manager = onThisDayManager] in
                Task { @MainActor in
                    guard let manager else { return }
                    await OnThisDayWidgetSnapshotWriter.shared.rebuild(
                        using: manager.yearGroups,
                        isMonthFallback: manager.isMonthFallback,
                        permissionGranted: Self.hasPhotoPermission()
                    )
                }
            }

            // 图库真删除监听：触发强制刷新 + 重建快照
            OnThisDayLibraryObserver.shared.onLibraryChanged = { [weak manager = onThisDayManager] in
                guard let manager else { return }
                await manager.fetchOnThisDay(forceRefresh: true)
                await OnThisDayWidgetSnapshotWriter.shared.rebuild(
                    using: manager.yearGroups,
                    isMonthFallback: manager.isMonthFallback,
                    permissionGranted: Self.hasPhotoPermission(),
                    force: true
                )
            }
            OnThisDayLibraryObserver.shared.start()

            // 若 deep link 在本视图创建前已到达（welcome/会员阶段），消费初始值
            if let initialYear = pendingDeepLinkYear {
                Task { await resolveAndNavigateIfNeeded(year: initialYear) }
            }

            AppAnalytics.screen(selectedTab.analyticsName)
            #if DEBUG
            if CommandLine.arguments.contains("-view_trash") {
                photoManager.showTrash = true
            }
            if CommandLine.arguments.contains("-view_cleanup_result") {
                photoManager.lastCleanupResult = CleanupResult(deletedCount: 12, freedBytes: 154_000_000)
            }
            #endif
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
                // 默认 0.72 黄金比例高度呈现，展示更多照片行数，用户上滑可展开为全屏（large）
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
        }
        // 清理完成面板：贴底悬浮卡（非全屏），背景透出并变暗，样式对齐自由画布引导卡
        .overlay {
            if let result = photoManager.lastCleanupResult {
                CleanupResultView(result: result) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        photoManager.lastCleanupResult = nil
                    }
                    ReviewPromptManager.shared.requestReviewIfAppropriate(deletedCount: result.deletedCount, requestReview: requestReview)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Widget Deep Link & Snapshot

    private static func hasPhotoPermission() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    private func writeWidgetSnapshot(force: Bool) async {
        await OnThisDayWidgetSnapshotWriter.shared.rebuild(
            using: onThisDayManager.yearGroups,
            isMonthFallback: onThisDayManager.isMonthFallback,
            permissionGranted: Self.hasPhotoPermission(),
            force: force
        )
    }

    /// 消费 widget deep link：等数据就绪后按年份跳进对应「往年今日」详情页
    private func resolveAndNavigateIfNeeded(year: Int) async {
        selectedTab = .albums

        // 确保管理器数据已加载（冷启动时 await 在途预热任务）
        await onThisDayManager.ensureLoaded()
        if onThisDayManager.yearGroups.isEmpty && Self.hasPhotoPermission() {
            await onThisDayManager.fetchOnThisDay(forceRefresh: true)
        }

        // year == -1：空态跳转，只切到回忆 Tab，不 push 详情
        guard year >= 0 else {
            pendingDeepLinkYear = nil
            return
        }

        // 目标年份不存在（可能被真删）时回退最新一组
        let group = onThisDayManager.yearGroups.first { $0.year == year }
            ?? onThisDayManager.yearGroups.first
        guard let group else {
            pendingDeepLinkYear = nil
            return
        }

        albumsPath = NavigationPath()   // 清掉旧栈，避免 deep link 反复叠加
        albumsPath.append(AlbumsDestination.onThisDay(group))
        pendingDeepLinkYear = nil
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
                        },
                        onMyAlbumsList: {
                            albumsPath.append(AlbumsDestination.albumList)
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
                case .albumList:
                    if let albumMgr = albumManager {
                        MyAlbumsListView(
                            albumManager: albumMgr,
                            onAlbumSelect: { album in
                                selectedAlbum = album
                                Task { [album] in
                                    await albumMgr.fetchPhotos(in: album)
                                    guard selectedAlbum?.id == album.id else { return }
                                    albumsPath.append(AlbumsDestination.albumDetail(album.id))
                                }
                            }
                        )
                    }
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

#if DEBUG
#Preview {
    MainTabView(pendingDeepLinkYear: .constant(nil))
        .environmentObject(PhotoManager.mock)
        .environmentObject(MembershipManager())
        .environmentObject(StatisticsManager())
        .environment(GridSettings())
}
#endif

// MARK: - TabBar 未选中色（标准 appearance 着色，不再 swizzle）
extension UITabBar {
    private static var hasSwizzled = false

    /// 整体加深的未选中深炭灰（浅色 #545458 对比度 5.8:1，深色 #98989D 银炭灰）
    static let unselectedTabColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.60, green: 0.60, blue: 0.64, alpha: 1.0)
            : UIColor(red: 0.33, green: 0.33, blue: 0.35, alpha: 1.0)
    }
}

// MARK: - iOS 27+ / iPhone Duo 标签栏底置修饰器
private struct DefaultTabBarPlacementModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.defaultTabBarPlacement(.tabBar)
        } else {
            content
        }
    }
}

