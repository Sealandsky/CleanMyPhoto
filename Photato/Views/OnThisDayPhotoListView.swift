import SwiftUI
import Photos
import Combine

// MARK: - On This Day Photo List View
/// 「过去的今天」专属照片列表二级页：
/// 1. 顶部 Hero Banner：首张图片高斯模糊（blur background）作为沉浸背景，平滑渐变融入底色；
/// 2. 大标题区域加高，展示「日 月」（如 29 Oct / 10月29日）粗体与浅色年份（如 2023）；
/// 3. 上滑滚动后标题不进入 titlebar，保持顶栏清爽透明；
/// 4. 浮动毛玻璃圆形返回键与胶囊「选择」按钮；
/// 5. 自适应网格（AdaptivePhotoGrid）浏览，支持原图比例/固定比例，长按多选与单手滑动手势移入废纸篓；
/// 6. 点击任意素材以 Zoom 动画无缝推入 FullscreenPhotoBrowser 全屏详情。
struct OnThisDayPhotoListView: View {
    let group: OnThisDayYearGroup
    @ObservedObject var photoManager: PhotoManager
    var onPhotoSelect: ((PhotoAsset) -> Void)? = nil
    var scrollToPhotoID: String? = nil

    @Environment(GridSettings.self) private var gridSettings
    @Environment(\.dismiss) private var dismiss

    @State private var selectionManager = SelectionManager()
    @State private var totalSizeText: String = ""
    @State private var isFullscreenMode = false
    @State private var canSelectPhoto = true
    @State private var currentPhotoID: String? = nil
    @State private var targetScrollPhotoID: String? = nil
    @State private var showFavoriteDeleteAlert = false
    @State private var localPhotos: [PhotoAsset]
    @State private var coverImage: UIImage?
    @AppStorage("onThisDay_isCanvasMode") private var isCanvasMode: Bool = false
    @Namespace private var photoTransitionNamespace

    init(
        group: OnThisDayYearGroup,
        photoManager: PhotoManager,
        onPhotoSelect: ((PhotoAsset) -> Void)? = nil,
        scrollToPhotoID: String? = nil
    ) {
        self.group = group
        self.photoManager = photoManager
        self.onPhotoSelect = onPhotoSelect
        self.scrollToPhotoID = scrollToPhotoID
        self._localPhotos = State(initialValue: group.photos)

        // 同步直接命中卡片已解压缩并驻留内存的缩略图缓存（第 0 帧直出，彻底杜绝转场闪变）
        let cached = PhotoImageCache.shared.get(
            for: group.coverAsset.id,
            targetSize: CGSize(width: 240, height: 320),
            isHighQuality: false
        ) ?? PhotoImageCache.shared.getPlaceholder(for: group.coverAsset.id)
        self._coverImage = State(initialValue: cached)
    }

    /// 过滤掉已放入待删除废纸篓的素材，实现响应式删除
    private var displayedPhotos: [PhotoAsset] {
        localPhotos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if isCanvasMode {
                OnThisDayFreeformCanvasView(
                    group: group,
                    photoManager: photoManager,
                    onBlocked: {
                        showFavoriteDeleteAlert = true
                    }
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // 1. 顶部日期与信息展示
                            if !selectionManager.isSelectMode {
                                headerInfoView
                            }

                            // 2. 照片内容区
                            if displayedPhotos.isEmpty {
                                emptyStateView
                            } else {
                                photoGridView
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .background(Color.pageBackground)
                    .allowsHitTesting(canSelectPhoto && !isFullscreenMode)
                    .onChange(of: scrollToPhotoID) { _, newValue in
                        handleScrollToPhotoID(newValue, proxy: proxy)
                    }
                    .onAppear {
                        handleOnAppear(proxy: proxy)
                    }
                    .onChange(of: targetScrollPhotoID) { _, newValue in
                        if let photoID = newValue {
                            withTransaction(Transaction(animation: nil)) {
                                proxy.scrollTo(photoID, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: isFullscreenMode) { oldValue, newValue in
                        handleFullscreenChange(oldValue: oldValue, newValue: newValue, proxy: proxy)
                    }
                    .scrollIndicators(.hidden)
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isCanvasMode)
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
                if !isCanvasMode {
                    VStack(spacing: 2) {
                        Text(navigationBarTitle)
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if !selectionManager.isSelectMode {
                            Text(photoCountAndSizeText)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
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
                } else if isCanvasMode {
                    PendingPhotosEntryButton(isLiquidGlass: true)
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
                        targetScrollPhotoID = photo.id
                    },
                    onDismiss: {
                        isFullscreenMode = false
                    }
                )
                .environmentObject(photoManager)
                .navigationTransition(.zoom(sourceID: currentPhotoID ?? photoID, in: photoTransitionNamespace))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectionManager.isSelectMode)
        .alert(String(localized: "Cannot Delete"), isPresented: $showFavoriteDeleteAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "This photo is in your favorites. Remove from favorites first before deleting."))
        }
        .overlay(alignment: .bottomLeading) {
            if !selectionManager.isSelectMode {
                ViewModeSwitcher(isCanvasMode: $isCanvasMode)
                    .padding(.leading, 18)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Navigation Bar Title
    private var navigationBarTitle: String {
        if selectionManager.isSelectMode {
            return String(localized: "\(selectionManager.count) Selected")
        } else if isCanvasMode {
            return ""
        } else {
            return "\(mainDateText) · \(yearText)"
        }
    }

    // MARK: - Header Info View
    private var headerInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "On This Day"))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mainDateText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(yearText)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()
            }

            subtitleInfoView
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Photo Grid View
    private var photoGridView: some View {
        AdaptivePhotoGrid(photos: displayedPhotos) { (photo: PhotoAsset, index: Int) in
            cellForPhoto(photo, index: index)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func cellForPhoto(_ photo: PhotoAsset, index: Int) -> some View {
        let isSelected = selectionManager.isSelected(photo.id)
        let isSelectMode = selectionManager.isSelectMode
        let isFav = photoManager.isFavorite(photo)

        let cell = PhotoCell(
            photo: photo,
            isSelected: isSelected,
            isSelectMode: isSelectMode
        )
        .id(photo.id)
        .matchedTransitionSource(id: photo.id, in: photoTransitionNamespace) { source in
            source.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTapPhoto(photo)
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
            isEnabled: !isSelectMode && !isFullscreenMode,
            isFavorite: isFav,
            onTrash: { targetPhoto in
                photoManager.addToTrash(targetPhoto)
            },
            onBlocked: {
                showFavoriteDeleteAlert = true
            }
        )
    }

    private func handleTapPhoto(_ photo: PhotoAsset) {
        if selectionManager.isSelectMode {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectionManager.toggle(photo.id)
            }
        } else {
            guard canSelectPhoto && !isFullscreenMode else { return }
            canSelectPhoto = false
            currentPhotoID = photo.id
            targetScrollPhotoID = nil
            isFullscreenMode = true
            onPhotoSelect?(photo)
        }
    }

    // MARK: - Scroll & Lifecycle Helpers

    private func handleScrollToPhotoID(_ photoID: String?, proxy: ScrollViewProxy) {
        guard let photoID = photoID else { return }
        let photoExists = displayedPhotos.contains(where: { $0.id == photoID })
        if photoExists {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withTransaction(Transaction(animation: nil)) {
                    proxy.scrollTo(photoID, anchor: .center)
                }
            }
        }
    }

    private func handleOnAppear(proxy: ScrollViewProxy) {
        loadCoverImageIfNeeded()
        totalSizeText = SizeCache.load("onthisday_\(group.id)") ?? ""
        if let photoID = scrollToPhotoID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withTransaction(Transaction(animation: nil)) {
                    proxy.scrollTo(photoID, anchor: .center)
                }
            }
        }
        calculateSize()
    }

    /// 兜底：若极端情况下同步内存缓存未命中，异步轻量拉取缩略图并平滑渐显
    private func loadCoverImageIfNeeded() {
        guard coverImage == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        _ = PhotoAssetImageManager.shared.requestImage(
            for: group.coverAsset.asset,
            targetSize: CGSize(width: 240, height: 320),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let image = image {
                Task { @MainActor in
                    if coverImage == nil {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            coverImage = image
                        }
                    }
                }
            }
        }
    }

    private func handleFullscreenChange(oldValue: Bool, newValue: Bool, proxy: ScrollViewProxy) {
        if oldValue && !newValue {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                canSelectPhoto = true
            }
            if let photoID = targetScrollPhotoID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withTransaction(Transaction(animation: nil)) {
                        proxy.scrollTo(photoID, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Title & Date Helpers

    private var mainDateText: String {
        let date = group.photos.first?.asset.creationDate ?? Date()
        if group.isMonthFallback {
            return date.formatted(.dateTime.month())
        } else {
            return date.formatted(.dateTime.month().day())
        }
    }

    private var yearText: String {
        String(group.year)
    }

    // MARK: - Subtitle Info View (照片数量 + 容量大小 + 图钉前置地名)
    private var subtitleInfoView: some View {
        HStack(spacing: 4) {
            Text(photoCountAndSizeText)
                .font(.system(size: 13, weight: .medium, design: .rounded))

            if let location = group.locationName, !location.isEmpty {
                Text("·")
                    .font(.system(size: 13, weight: .medium, design: .rounded))

                HStack(spacing: 3) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11, weight: .semibold))
                    Text(location)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
            }
        }
        .foregroundColor(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var photoCountAndSizeText: String {
        let countText = String(localized: "\(displayedPhotos.count) Photos")
        if totalSizeText.isEmpty {
            return countText
        }
        return "\(countText) · \(totalSizeText)"
    }

    // MARK: - Size Calculation
    private func calculateSize() {
        let assets = displayedPhotos.map(\.asset)
        Task {
            let totalSize = await Task.detached(priority: .utility) {
                await PHAssetSizeHelper.calculateTotalSize(for: assets)
            }.value
            SizeCache.save("onthisday_\(group.id)", size: totalSize)
            let newText = ByteFormatter.format(totalSize)
            if newText != totalSizeText {
                totalSizeText = newText
            }
        }
    }

    // MARK: - Empty State
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
