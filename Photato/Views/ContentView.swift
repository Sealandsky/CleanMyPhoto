import SwiftUI
import Photos

struct ContentView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var statisticsManager: StatisticsManager

    // 由 MainTabView 持有：全屏态控制底部栏显隐
    @Binding var isFullscreenMode: Bool

    // 「回忆」Tab 再次点击的滚顶信号（MainTabView 递增传入）
    @Binding var discoverScrollToTop: Int

    @State private var currentPhotoID: String? = nil
    @State private var scrollToPhotoID: String? = nil

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
        .animation(.easeInOut(duration: 0.2), value: isFullscreenMode)
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
                scrollToTopSignal: discoverScrollSignal
            )
            .navigationTitle(String(localized: "Memories"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(alignment: .top) {
                TopBlurFadeBackground(height: 200)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    formatFilterMenu
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
                        },
                        onDismiss: {
                            isFullscreenMode = false
                        }
                    )
                    .environmentObject(photoManager)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - 页面右上角格式筛选器（原生系统下拉菜单）
    @ViewBuilder
    private var formatFilterMenu: some View {
        Menu {
            ForEach(MediaFormatFilter.allCases) { filter in
                Button {
                    Task {
                        await discoverManager.setFilter(filter)
                    }
                } label: {
                    if discoverManager.selectedFilter == filter {
                        Label(filter.localizedText, systemImage: "checkmark")
                    } else {
                        Label(filter.localizedText, systemImage: filter.systemImage)
                    }
                }
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
        isFullscreenMode: .constant(false),
        discoverScrollToTop: .constant(0)
    )
    .environmentObject(PhotoManager())
    .environmentObject(StatisticsManager())
}
