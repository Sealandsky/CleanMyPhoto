

import SwiftUI
import Photos

enum MainTab: String, CaseIterable {
    case discover
    case allPhotos
    case timeline

    var localizedText: String {
        switch self {
        case .allPhotos:
            return String(localized: "Library")
        case .timeline:
            return String(localized: "Timeline")
        case .discover:
            return String(localized: "Discover")
        }
    }

    var icon: String {
        switch self {
        case .allPhotos:
            return "photo.on.rectangle.angled"
        case .timeline:
            return "calendar"
        case .discover:
            return "sparkle.magnifyingglass"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var statisticsManager: StatisticsManager

    // 由 MainTabView 持有：全屏态控制底部栏显隐；timelinePath 为时间线子页的导航路径
    @Binding var isFullscreenMode: Bool
    @Binding var timelinePath: NavigationPath

    // 「重温」Tab 再次点击的滚顶信号（MainTabView 递增传入）
    @Binding var discoverScrollToTop: Int

    @State private var currentPhotoID: String? = nil
    @State private var scrollToPhotoID: String? = nil

    // 相簿相关状态（相簿已抽离为独立底部 Tab，见 MainTabView）
    @State private var selectedTab: MainTab = .discover // 发现为首个 Tab，默认选中
    @State private var systemAlbumManager: SystemAlbumManager?
    @State private var selectedMonthAlbum: MonthAlbum? = nil
    @StateObject private var discoverManager = DiscoverManager()
    // 发现页滚顶信号：递增驱动 DiscoverView 滚回顶部
    @State private var discoverScrollSignal = 0

    // 滚动偏移状态
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        Group {
            if photoManager.authorizationStatus == .notDetermined {
                permissionView
            } else if photoManager.authorizationStatus == .authorized || photoManager.authorizationStatus == .limited {
                mainView
            } else {
                deniedView
            }
        }
        .task {
            guard !photoManager.hasLoadedOnce else { return }

            if photoManager.authorizationStatus == .notDetermined {
                await photoManager.requestAuthorization()
            } else if photoManager.authorizationStatus == .authorized || photoManager.authorizationStatus == .limited {
                await photoManager.fetchAllPhotos()
            }

            if systemAlbumManager == nil {
                systemAlbumManager = SystemAlbumManager()
            }

            // 「发现」为默认首位 Tab：启动时若正处于发现页则立即采样
            // （onChange 仅在 Tab 变化时触发，覆盖不了默认选中的首次进入）
            if selectedTab == .discover, !discoverManager.hasLoadedOnce {
                await discoverManager.refresh()
            }
        }
        .alert(String(localized: "Error"), isPresented: .constant(photoManager.errorMessage != nil)) {
            Button(String(localized: "OK")) {
                photoManager.errorMessage = nil
            }
        } message: {
            if let errorMessage = photoManager.errorMessage {
                Text(errorMessage)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: photoManager.isSelectMode)
        .animation(.easeInOut(duration: 0.2), value: isFullscreenMode)
        // 页面切换时的状态重置与懒加载（原挂载在顶部 Tab 栏视图上，
        // 改造为下拉选择器后迁至 body 层，逻辑保持不变）
        // 「重温」Tab 再次点击：先切回发现子页，再触发滚顶
        .onChange(of: discoverScrollToTop) { _, _ in
            if selectedTab != .discover {
                selectedTab = .discover
            }
            discoverScrollSignal += 1
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            selectedTabBeforeSwitch = oldValue
            scrollToPhotoID = nil
            isFullscreenMode = false
            currentPhotoID = nil

            timelinePath = NavigationPath()
            selectedMonthAlbum = nil

            // 发现页懒加载：首次切到该 Tab 才随机采样（与相簿页策略一致）
            if newValue == .discover, !discoverManager.hasLoadedOnce {
                Task {
                    await discoverManager.refresh()
                }
            }
        }
    }

    // MARK: - Permission View
    private var permissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 80, design: .rounded))
                .foregroundColor(.blue)

            VStack(spacing: 12) {
                Text(String(localized: "Photo Access Required"))
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)

                Text(String(localized: "Photato needs access to your photo library to help you organize and clean up unwanted photos."))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            ProgressView()
                .scaleEffect(1.2)
        }
        .padding()
    }

    // MARK: - Denied View
    private var deniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80, design: .rounded))
                .foregroundColor(.orange)

            VStack(spacing: 12) {
                Text(String(localized: "Access Denied"))
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)

                Text(String(localized: "To use Photato, please enable photo library access in Settings."))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button(String(localized: "Open Settings")) {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Main View
    private var mainView: some View {
        ZStack {
            contentViews
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Fullscreen Bindings
    private var isDiscoverFullscreenBinding: Binding<Bool> {
        Binding(
            get: { isFullscreenMode && selectedTab == .discover },
            set: { newValue in
                if !newValue && selectedTab == .discover {
                    isFullscreenMode = false
                }
            }
        )
    }

    private var isLibraryFullscreenBinding: Binding<Bool> {
        Binding(
            get: { isFullscreenMode && selectedTab == .allPhotos },
            set: { newValue in
                if !newValue && selectedTab == .allPhotos {
                    isFullscreenMode = false
                }
            }
        )
    }

    private var isTimelineFullscreenBinding: Binding<Bool> {
        Binding(
            get: { isFullscreenMode && selectedTab == .timeline },
            set: { newValue in
                if !newValue && selectedTab == .timeline {
                    isFullscreenMode = false
                }
            }
        )
    }

    // MARK: - Content Views
    private var contentViews: some View {
        ZStack {
            libraryNavigationView
                .opacity(selectedTab == .allPhotos ? 1 : 0)
                .allowsHitTesting(selectedTab == .allPhotos)

            timelineNavigationView
                .opacity(selectedTab == .timeline ? 1 : 0)
                .allowsHitTesting(selectedTab == .timeline)

            // 发现 Tab：与其他页相同的 opacity + hitTest 切换方式，零样式改动
            discoverNavigationView
                .opacity(selectedTab == .discover ? 1 : 0)
                .allowsHitTesting(selectedTab == .discover)
        }
        .background(Color(UIColor.systemGroupedBackground)) // 固定背景，防止露黑
    }

    @State private var selectedTabBeforeSwitch: MainTab = .allPhotos

    // MARK: - Library Navigation
    private var libraryNavigationView: some View {
        NavigationStack {
            applySharedTitleBar(to: photoListView)
                .navigationDestination(isPresented: isLibraryFullscreenBinding) {
                    if let photoID = currentPhotoID {
                        FullscreenPhotoBrowser(
                            photos: photoManager.displayedPhotos,
                            initialPhotoID: photoID,
                            onDelete: { photo in
                                photoManager.addToTrash(photo)
                            },
                            onFavoriteToggled: { _, _ in },
                            onActivePhotoChange: { photo, index in
                                currentPhotoID = photo.id
                                scrollToPhotoID = photo.id
                                photoManager.preloadAssets(photoIndex: index)
                            },
                            onDismiss: {
                                scrollToPhotoID = currentPhotoID
                                isFullscreenMode = false
                            }
                        )
                        .environmentObject(photoManager)
                    }
                }
        }
    }

    // MARK: - Navigation State
    private var isAtRootLevel: Bool {
        switch selectedTab {
        case .allPhotos:
            return true
        case .timeline:
            return timelinePath.isEmpty
        case .discover:
            return true
        }
    }

    // MARK: - App Title
    private var appTitle: String {
        switch selectedTab {
        case .allPhotos:
            return String(localized: "Library")
        case .timeline:
            return String(localized: "Timeline")
        case .discover:
            return String(localized: "Discover")
        }
    }

    // MARK: - Timeline Navigation
    private var timelineNavigationView: some View {
        NavigationStack(path: $timelinePath) {
            applySharedTitleBar(to: Group {
                if let systemAlbumMgr = systemAlbumManager {
                    PhotoGroupView(
                        albumManager: systemAlbumMgr,
                        photoManager: photoManager,
                        onMonthSelect: { monthAlbum in
                            selectedMonthAlbum = monthAlbum
                            timelinePath.append(TimelineDestination.monthPhotos(monthAlbum.id))
                        }
                    )
                } else {
                    loadingView
                }
            })
            .navigationDestination(for: TimelineDestination.self) { destination in
                switch destination {
                case .monthPhotos(_):
                    if let monthAlbum = selectedMonthAlbum {
                        SystemMonthPhotosView(
                            monthAlbum: monthAlbum,
                            photoManager: photoManager,
                            onPhotoSelect: { photo in
                                currentPhotoID = photo.id
                                scrollToPhotoID = nil
                                isFullscreenMode = true
                            },
                            scrollToPhotoID: scrollToPhotoID
                        )
                        .navigationDestination(isPresented: isTimelineFullscreenBinding) {
                            if let photoID = currentPhotoID {
                                FullscreenPhotoBrowser(
                                    photos: monthAlbum.photoAssets.filter { !photoManager.pendingDeletionIDs.contains($0.id) },
                                    initialPhotoID: photoID,
                                    onDelete: { photo in
                                        photoManager.addToTrash(photo)
                                    },
                                    onFavoriteToggled: { _, _ in },
                                    onActivePhotoChange: { photo, index in
                                        currentPhotoID = photo.id
                                        scrollToPhotoID = photo.id
                                        photoManager.preloadAssets(photoIndex: index)
                                    },
                                    onDismiss: {
                                        scrollToPhotoID = currentPhotoID
                                        isFullscreenMode = false
                                    }
                                )
                                .environmentObject(photoManager)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: timelinePath) { oldValue, newValue in
            if newValue.isEmpty {
                selectedMonthAlbum = nil
                if !oldValue.isEmpty, let systemAlbumMgr = systemAlbumManager {
                    Task {
                        await systemAlbumMgr.fetchYearAlbums()
                        await systemAlbumMgr.fetchAllMonths()
                    }
                }
            }
        }
    }

    // MARK: - Discover Navigation
    // 发现页：独立 NavigationStack，标题栏与其他三页共用（见 applySharedTitleBar）。
    // 点击照片通过 onPhotoSelect 打开原生推入的全屏详情页（FullscreenPhotoBrowser）
    private var discoverNavigationView: some View {
        NavigationStack {
            applySharedTitleBar(to: DiscoverView(
                manager: discoverManager,
                onPhotoSelect: { photo in
                    currentPhotoID = photo.id
                    scrollToPhotoID = nil
                    isFullscreenMode = true
                },
                scrollToTopSignal: discoverScrollSignal
            ))
            .navigationDestination(isPresented: isDiscoverFullscreenBinding) {
                if let photoID = currentPhotoID {
                    FullscreenPhotoBrowser(
                        photos: discoverManager.photos,
                        initialPhotoID: photoID,
                        onDelete: { photo in
                            photoManager.addToTrash(photo)
                            discoverManager.removePhoto(photo)
                        },
                        onFavoriteToggled: { photo, isFavorite in
                            discoverManager.updateFavorite(photoID: photo.id, isFavorite: isFavorite)
                        },
                        onActivePhotoChange: { photo, _ in
                            currentPhotoID = photo.id
                        },
                        onDismiss: {
                            isFullscreenMode = false
                        }
                    )
                    .environmentObject(photoManager)
                }
            }
        }
    }

    // MARK: - 共享标题栏（发现/图库/时间线三个子页共用）
    /// 标题栏结构：标题居左大字号（滚动时系统自动收缩为 inline）+
    /// 右侧操作按钮组（Liquid Glass 质感）。
    /// 背景隐藏系统导航栏的硬分界模糊，改用 TopBlurFadeBackground 的
    /// 垂直渐变遮罩——模糊效果自上而下逐步衰减、柔和淡出
    private func applySharedTitleBar<V: View>(to content: V) -> some View {
        content
            .navigationTitle(appTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(alignment: .top) {
                TopBlurFadeBackground(height: 200)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    tabSelectorMenu
                }
            }
    }

    // MARK: - 页面下拉选择器（四个子页共用）
    /// 替代原顶部 Tab 栏的页面切换控件（系统 Menu，不做自定义样式）：
    /// - 保留原有全部 Tab 选项，当前选中项带 checkmark 回显
    /// - 点击外部区域由系统自动关闭菜单；重复点击/快速切换由系统防抖处理
    /// - 选项点击直接写 selectedTab，切换即完成页面切换，
    ///   原有 onChange 懒加载/状态重置逻辑完全复用（见 tabContent.onChange）
    private var tabSelectorMenu: some View {
        Menu {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    // 当前选中项带 checkmark 回显
                    if selectedTab == tab {
                        Label(tab.localizedText, systemImage: "checkmark")
                    } else {
                        Text(tab.localizedText)
                    }
                }
            }
        } label: {
            if #available(iOS 26.0, *) {
                // iOS 26+：toolbar 按钮由系统自动呈现 Liquid Glass 磨砂质感
                Image(systemName: "line.3.horizontal.decrease")
            } else {
                // iOS 18：磨砂圆钮回退
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    // MARK: - Photo List View
    private var photoListView: some View {
        PhotoListView(
            photoManager: photoManager,
            onPhotoSelect: { photo in
                currentPhotoID = photo.id
                scrollToPhotoID = nil
                isFullscreenMode = true
            },
            scrollToPhotoID: scrollToPhotoID,
            onScrollOffsetChanged: { offset in
                scrollOffset = offset
            }
        )
    }

    // MARK: - Loading View
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
        ContentView(
            isFullscreenMode: .constant(false),
            timelinePath: .constant(NavigationPath()),
            discoverScrollToTop: .constant(0)
        )
    }
