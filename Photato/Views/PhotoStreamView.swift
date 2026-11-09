import SwiftUI
import Photos

// MARK: - Photo Stream View
/// 纯粹沉浸式全量图片流视图（适用于「所有照片」与「时光归档月份相册」）：
/// 1. 采用 AdaptivePhotoGrid 连续沉浸瀑布流，完全跟随用户在设置中选择的原图比例/固定比例；
/// 2. 移除日期切断吸顶头，整屏无缝沉浸浏览；
/// 3. 单手交互：PhotoCell -> matchedTransitionSource -> swipeToTrash；
/// 4. 点击照片无缝 Zoom 放大进入 FullscreenPhotoBrowser；
/// 5. 右上角「选择」按钮支持滑动多选与批量放入废纸篓。
struct PhotoStreamView: View {
    let streamTitle: String
    var subtitle: String? = nil
    var initialPhotos: [PhotoAsset] = []
    var fetchPhotos: (() async -> [PhotoAsset])? = nil

    @ObservedObject var photoManager: PhotoManager
    @Environment(GridSettings.self) private var gridSettings

    @State private var localPhotos: [PhotoAsset] = []
    @State private var isLoading = false
    @State private var selectionManager = SelectionManager()
    @State private var isFullscreenMode = false
    @State private var currentPhotoID: String? = nil
    @State private var canSelectPhoto = true
    @State private var showFavoriteDeleteAlert = false
    @Namespace private var photoTransitionNamespace

    /// 响应式过滤掉已放入待删除废纸篓的素材
    private var displayedPhotos: [PhotoAsset] {
        localPhotos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isLoading && localPhotos.isEmpty {
                    loadingGrid
                        .padding(.top, 8)
                } else if displayedPhotos.isEmpty {
                    emptyStateView
                } else {
                    photoStreamContent
                }
            }
            .background(Color.pageBackground)
            .allowsHitTesting(canSelectPhoto && !isFullscreenMode)
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .onChange(of: selectionManager.isSelectMode) { _, newValue in
            photoManager.isSelectMode = newValue
        }
        .background(Color.pageBackground)
        .navigationTitle(navigationBarTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(selectionManager.isSelectMode)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if selectionManager.isSelectMode {
                    Button(String(localized: "Cancel")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectionManager.clearSelection()
                        }
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.primary)
                }
            }

            ToolbarItem(placement: .principal) {
                Text(navigationBarTitle)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            ToolbarItem(placement: .topBarTrailing) {
                if selectionManager.isSelectMode {
                    Button {
                        SoundManager.playAction()
                        let selected = displayedPhotos.filter { selectionManager.isSelected($0.id) }
                        for photo in selected {
                            photoManager.addToTrash(photo)
                        }
                        selectionManager.clearSelection()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text(String(localized: "Delete"))
                                .font(.system(.body, design: .rounded))
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .tint(.red)
                    .disabled(selectionManager.isEmpty)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectionManager.enterSelectMode()
                        }
                    } label: {
                        Text(String(localized: "Select"))
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .dynamicSecondaryNavigationBar()
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $isFullscreenMode) {
            if let photoID = currentPhotoID {
                FullscreenPhotoBrowser(
                    photos: displayedPhotos,
                    initialPhotoID: photoID,
                    onDelete: { photo in
                        photoManager.addToTrash(photo)
                    },
                    onFavoriteToggled: { photo, isFavorite in
                        if let index = localPhotos.firstIndex(where: { $0.id == photo.id }) {
                            localPhotos[index].isFavorite = isFavorite
                        }
                    },
                    onActivePhotoChange: { photo, _ in
                        currentPhotoID = photo.id
                    },
                    onDismiss: {
                        isFullscreenMode = false
                        canSelectPhoto = true
                    }
                )
                .environmentObject(photoManager)
                .navigationTransition(.zoom(sourceID: currentPhotoID ?? photoID, in: photoTransitionNamespace))
            }
        }
        .task {
            await loadInitialPhotos()
        }
        .alert(String(localized: "Cannot Delete"), isPresented: $showFavoriteDeleteAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "This photo is in your favorites. Remove from favorites first before deleting."))
        }
    }

    // MARK: - Navigation Bar Title
    private var navigationBarTitle: String {
        if selectionManager.isSelectMode {
            return String(localized: "\(selectionManager.count) Selected")
        }
        return streamTitle
    }

    // MARK: - Continuous Adaptive Waterfall Grid
    @ViewBuilder
    private var photoStreamContent: some View {
        AdaptivePhotoGrid(photos: displayedPhotos) { photo, index in
            let cell = PhotoCell(
                photo: photo,
                isSelected: selectionManager.isSelected(photo.id),
                isSelectMode: selectionManager.isSelectMode
            )
            .id(photo.id)
            .matchedTransitionSource(id: photo.id, in: photoTransitionNamespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selectionManager.isSelectMode {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectionManager.toggle(photo.id)
                    }
                } else {
                    guard canSelectPhoto && !isFullscreenMode else { return }
                    canSelectPhoto = false
                    currentPhotoID = photo.id
                    isFullscreenMode = true
                }
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectionManager.toggle(photo.id)
                }
            }
            .onAppear {
                photoManager.preheatAssets(around: index, in: displayedPhotos, columnCount: gridSettings.columnCount)
            }

            cell.swipeToTrash(
                photo: photo,
                isEnabled: !selectionManager.isSelectMode && !isFullscreenMode,
                isFavorite: photoManager.isFavorite(photo),
                onTrash: { targetPhoto in
                    photoManager.addToTrash(targetPhoto)
                },
                onBlocked: {
                    showFavoriteDeleteAlert = true
                }
            )
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)

        if !displayedPhotos.isEmpty {
            VStack(spacing: 4) {
                Text(String(localized: "\(displayedPhotos.count) Photos"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Text(String(localized: "Updated Just Now"))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Data Loading
    private func loadInitialPhotos() async {
        if !initialPhotos.isEmpty {
            self.localPhotos = initialPhotos
            return
        }

        if let fetch = fetchPhotos {
            isLoading = true
            let photos = await fetch()
            self.localPhotos = photos
            isLoading = false
        }
    }

    // MARK: - Loading & Empty States
    private var loadingGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: gridSettings.columnCount), spacing: 4) {
            ForEach(0..<18, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.systemGray5))
                    .aspectRatio(1.0, contentMode: .fit)
                    .shimmering(cornerRadius: 4)
            }
        }
        .padding(.horizontal, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48, design: .rounded))
                .foregroundColor(.secondary)
            Text(String(localized: "No Photos Found"))
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}
