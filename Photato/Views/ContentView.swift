import SwiftUI
import Photos

struct ContentView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var statisticsManager: StatisticsManager

    // 由 MainTabView 持有：全屏态控制底部栏显隐
    @Binding var isFullscreenMode: Bool

    // 「回忆」Tab 滚顶信号（外部可选传入，默认 0）
    var discoverScrollToTop: Int = 0

    @State private var currentPhotoID: String? = nil
    @State private var scrollToPhotoID: String? = nil
    @Namespace private var photoTransitionNamespace

    @StateObject private var discoverManager = DiscoverManager()
    // 回忆页滚顶信号：递增驱动 DiscoverView 滚回顶部
    @State private var discoverScrollSignal = 0

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
            if photoManager.authorizationStatus == .notDetermined {
                await photoManager.requestAuthorization()
            }

            // 首次进入 app 仅加载「全部」的图片，不加载分类下的图片
            if !discoverManager.hasLoadedOnce {
                discoverManager.selectedFilter = .all
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
        // 「回忆」Tab 再次点击：触发滚顶
        .onChange(of: discoverScrollToTop) { _, _ in
            discoverScrollSignal += 1
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

    // MARK: - Main View（独立「回忆」页）
    private var mainView: some View {
        NavigationStack {
            DiscoverView(
                manager: discoverManager,
                onPhotoSelect: { photo in
                    currentPhotoID = photo.id
                    scrollToPhotoID = nil
                    isFullscreenMode = true
                },
                scrollToTopSignal: discoverScrollSignal,
                scrollToPhotoID: scrollToPhotoID,
                transitionNamespace: photoTransitionNamespace
            )
            .navigationTitle(String(localized: "Memories"))
            .navigationBarTitleDisplayMode(.large)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .toolbar {
                // 第一组：筛选菜单，独立胶囊
                ToolbarItemGroup(placement: .topBarTrailing) {
                    formatFilterMenu
                }

                if #available(iOS 26.0, *) {
                    // Spacer 放在 ItemGroup 外面同级，切断分组
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                // 第二组：待处理照片按钮，独立胶囊
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PendingPhotosEntryButton()
                }
            }
            .navigationDestination(isPresented: $isFullscreenMode) {
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
                            // 切图即请求网格定位：详情页仍盖着网格，滚动发生在
                            // 遮盖之下用户无感知，返回时已就位（不依赖 pop 信号——
                            // 侧滑返回时 onDismiss 与 binding 变化时机均不可靠）
                            scrollToPhotoID = photo.id
                        },
                        onDismiss: {
                            // 内部退出路径（删空批次/下滑关闭）
                            isFullscreenMode = false
                        }
                    )
                    .environmentObject(photoManager)
                    .navigationTransition(.zoom(sourceID: currentPhotoID ?? photoID, in: photoTransitionNamespace))
                    // 返回定位（转场开始时机）：binding 在 pop 转场开始的瞬间被
                    // 置 false——此刻立即定位，0.35s 转场窗口足够掩盖滚动（视觉
                    // 上网格随转场露出时已在目标位）。切图时的实时定位（上方
                    // onActivePhotoChange）与销毁兜底（onDisappear）多路覆盖同一
                    // 目标，谁先生效用谁
                    .onDisappear {
                        scrollToPhotoID = currentPhotoID
                    }
                }
            }
            // pop 转场开始即定位：比 onDisappear（转场结束）早 0.35s，
            // 与切图时的实时定位、销毁兜底共同多路覆盖
            .onChange(of: isFullscreenMode) { oldValue, newValue in
                if oldValue && !newValue {
                    scrollToPhotoID = currentPhotoID
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - 页面右上角格式筛选器（原生系统下拉菜单）
    @ViewBuilder
    private var formatFilterMenu: some View {
        Menu {
            Picker(
                selection: Binding(
                    get: { discoverManager.selectedFilter },
                    set: { newFilter in
                        Task {
                            await discoverManager.setFilter(newFilter)
                        }
                    }
                )
            ) {
                ForEach(MediaFormatFilter.allCases) { filter in
                    Label(filter.localizedText, systemImage: filter.systemImage)
                        .tag(filter)
                }
            } label: {
                Text(String(localized: "Filter"))
            }
        } label: {
            filterMenuLabel
        }
    }

    @ViewBuilder
    private var filterMenuLabel: some View {
        if discoverManager.selectedFilter == .all {
            // 全部分类下：纯图标排版，系统原生菜单颜色
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
        } else {
            // 选中某个分类：系统原生颜色，文本+图标排版（文字大一点，图标与默认态保持一致为 15pt）
            HStack(spacing: 4) {
                Text(discoverManager.selectedFilter.localizedText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.primary)
            .frame(height: 32)
        }
    }
}

#Preview {
    ContentView(
        isFullscreenMode: .constant(false)
    )
    .environmentObject(PhotoManager())
    .environmentObject(StatisticsManager())
}
