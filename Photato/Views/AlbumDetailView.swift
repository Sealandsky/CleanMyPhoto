import SwiftUI
import Photos
import PhotosUI

// MARK: - Push Open Transition (Smooth horizontal accordion expand without bounce)
struct WidthExpandModifier: AnimatableModifier {
    var progress: CGFloat // 0.0 to 1.0

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(width: max(0.001, 96 * progress), height: 108, alignment: .leading)
            .clipped()
            .opacity(progress)
    }
}

extension AnyTransition {
    static var pushOpen: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: WidthExpandModifier(progress: 0),
                identity: WidthExpandModifier(progress: 1)
            ),
            removal: .opacity
        )
    }
}

// MARK: - Album Detail View (Secondary Page)
/// 相簿二级概览页：
/// 1. 【你的照片】：横向单行排列当前相簿的照片，点击整行标题栏可推入三级全量照片网格；
///    添加新照片时具有平滑的列表右移与图片出现动画。
/// 2. 【更多适合这个相簿的照片】：原图比例瀑布流展示 Vision 相似度匹配推荐的照片；
///    右上角大圆角毛玻璃 '+' 按钮，点击一键加入当前相簿。
struct AlbumDetailView: View {
    @ObservedObject var albumManager: AlbumManager
    @ObservedObject var photoManager: PhotoManager
    let album: AlbumModel
    let onViewAllTapped: () -> Void

    @State private var recommendedPhotos: [PhotoAsset]
    @State private var isLoadingRecommendations: Bool
    @State private var addingPhotoIDs = Set<String>()
    @State private var addedPhotoIDs = Set<String>()
    @State private var isFullscreenMode = false
    @State private var fullscreenPhotos: [PhotoAsset] = []
    @State private var currentPhotoID: String? = nil
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var isProcessingPickedPhotos = false

    init(
        albumManager: AlbumManager,
        photoManager: PhotoManager,
        album: AlbumModel,
        onViewAllTapped: @escaping () -> Void
    ) {
        self.albumManager = albumManager
        self.photoManager = photoManager
        self.album = album
        self.onViewAllTapped = onViewAllTapped

        let currentPhotos = albumManager.displayedAlbumPhotos
        if let cached = albumManager.getCachedRecommendations(for: album.id, currentPhotos: currentPhotos) {
            _recommendedPhotos = State(initialValue: cached)
            _isLoadingRecommendations = State(initialValue: false)
        } else {
            _recommendedPhotos = State(initialValue: [])
            _isLoadingRecommendations = State(initialValue: true)
        }
    }

    private var albumPhotos: [PhotoAsset] {
        albumManager.displayedAlbumPhotos
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 36) {
                // 模块一：【你的照片】
                yourPhotosSection

                // 模块二：【更多适合这个相簿的照片】
                morePhotosSection
            }
            .padding(.top, 12)
            .padding(.bottom, 90) // 底部边距防止遮挡
        }
        .refreshable {
            await loadRecommendations(force: true)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .scrollIndicators(.hidden)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(alignment: .top) {
            TopBlurFadeBackground(height: 200)
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $isFullscreenMode) {
            if let photoID = currentPhotoID {
                FullscreenPhotoBrowser(
                    photos: fullscreenPhotos,
                    initialPhotoID: photoID,
                    onDelete: { photo in
                        photoManager.addToTrash(photo)
                        recommendedPhotos.removeAll(where: { $0.id == photo.id })
                    },
                    onFavoriteToggled: { photo, isFavorite in
                        albumManager.updateFavorite(photoID: photo.id, isFavorite: isFavorite)
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
        .task {
            await loadRecommendations()
        }
        .onChange(of: selectedPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await handlePickedPhotos(items)
            }
        }
    }

    // MARK: - Module 1: Your Photos
    private var yourPhotosSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 标题栏：照片数量作为副标题展示在主标题下方
            Button {
                onViewAllTapped()
            } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(String(localized: "Your Photos"))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }

                        Text(String(localized: "\(albumPhotos.count) Photos"))
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(String(localized: "View All"))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.accentColor)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            // 横向滑动照片列表
            if albumPhotos.isEmpty {
                emptyAlbumPlaceholder
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(albumPhotos.prefix(50))) { photo in
                            yourPhotoCard(photo)
                                .padding(.trailing, 10)
                                .transition(.pushOpen)
                                .onTapGesture {
                                    fullscreenPhotos = albumPhotos
                                    currentPhotoID = photo.id
                                    isFullscreenMode = true
                                }
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .defaultScrollAnchor(.leading)
            }
        }
    }

    // MARK: - Your Photo Card
    private func yourPhotoCard(_ photo: PhotoAsset) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemFill))

            AssetImage(
                asset: photo.asset,
                targetSize: CGSize(width: 600, height: 750),
                contentMode: .fill,
                placeholderColor: Color(UIColor.secondarySystemFill)
            )
            .id(photo.id)
            .scaledToFill()
            .frame(width: 86, height: 108)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if photo.isVideo {
                HStack(spacing: 2) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 8))
                    if let duration = photo.videoDuration {
                        Text(duration)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7))
                .clipShape(Capsule())
                .padding(5)
            }
        }
        .frame(width: 86, height: 108)
    }

    private var emptyAlbumPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text(String(localized: "No Photos in Album"))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemFill))
        )
    }

    // MARK: - Module 2: More Photos for This Album
    private var morePhotosSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 保留原有更多图片的标题（在任何状态下始终保留）
            HStack(spacing: 6) {
                Text(String(localized: "More Photos for This Album"))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                if !isLoadingRecommendations && !recommendedPhotos.isEmpty {
                    Text("\(recommendedPhotos.count)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)

            if isLoadingRecommendations && recommendedPhotos.isEmpty {
                // 仅首次进入且无缓存时显示骨架屏，避免每次都加载
                skeletonGrid
            } else if !recommendedPhotos.isEmpty {
                MasonryGridContent(photos: recommendedPhotos, columnCount: 2) { photo in
                    RecommendedPhotoCell(
                        photo: photo,
                        isAdding: addingPhotoIDs.contains(photo.id),
                        isAdded: addedPhotoIDs.contains(photo.id),
                        onAdd: {
                            addPhotoToAlbum(photo)
                        },
                        onTap: {
                            fullscreenPhotos = recommendedPhotos
                            currentPhotoID = photo.id
                            isFullscreenMode = true
                        }
                    )
                    .id(photo.id)
                }
                .padding(.horizontal, 16)
            } else {
                // 空卡状态：相簿已整理完毕
                albumCompleteCard
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Skeleton Loading (Waterfall placeholder)
    private var skeletonGrid: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .shimmering()
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1.0, contentMode: .fit)
                    .shimmering()
            }
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1.0, contentMode: .fit)
                    .shimmering()
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .shimmering()
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Album Complete State
    private var albumCompleteCard: some View {
        VStack(spacing: 20) {
            // 顶部成就图标徽章
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.16), Color.teal.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green, Color.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 4)

            // 文案说明
            VStack(spacing: 6) {
                Text(String(localized: "Album is Well Organized"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(String(localized: "All matching photos in your library are already in this album."))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
            }

            // 操作按钮：上下排布（去掉全屏放映浏览）
            VStack(spacing: 12) {
                // 按钮 1：从图库手动挑选照片
                PhotosPicker(
                    selection: $selectedPickerItems,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 8) {
                        if isProcessingPickedPhotos {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                        }

                        Text(isProcessingPickedPhotos
                             ? String(localized: "Adding Photos...")
                             : String(localized: "Add Photos from Library"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isProcessingPickedPhotos)

                // 按钮 2：查看全部照片
                Button {
                    onViewAllTapped()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.accentColor)
                        Text(String(localized: "View All Photos"))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(UIColor.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
    }

    // MARK: - Actions
    private func addPhotoToAlbum(_ photo: PhotoAsset) {
        guard !addingPhotoIDs.contains(photo.id) && !addedPhotoIDs.contains(photo.id) else { return }
        _ = addingPhotoIDs.insert(photo.id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                // 1. PhotoKit 写入相簿并推入相簿列表最前（触发平滑推开展开动画）
                _ = try await albumManager.addAssetToAlbum(photo.asset, in: album)

                withAnimation(.easeInOut(duration: 0.25)) {
                    _ = addedPhotoIDs.insert(photo.id)
                    _ = addingPhotoIDs.remove(photo.id)
                }

                // 2. 推荐卡片展示成功状态后，平滑移出推荐列表
                try? await Task.sleep(nanoseconds: 250_000_000)
                withAnimation(.easeInOut(duration: 0.28)) {
                    recommendedPhotos.removeAll(where: { $0.id == photo.id })
                    _ = addedPhotoIDs.remove(photo.id)
                }

                // 同步更新缓存
                albumManager.cacheRecommendations(recommendedPhotos, for: album.id, currentPhotos: albumPhotos)
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = addingPhotoIDs.remove(photo.id)
                }
                print("Failed to add photo to album: \(error)")
            }
        }
    }

    private func handlePickedPhotos(_ items: [PhotosPickerItem]) async {
        isProcessingPickedPhotos = true
        defer {
            isProcessingPickedPhotos = false
            selectedPickerItems = []
        }

        let assetIDs = items.compactMap(\.itemIdentifier)
        guard !assetIDs.isEmpty else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        var assetsToAdd: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if !albumPhotos.contains(where: { $0.id == asset.localIdentifier }) {
                assetsToAdd.append(asset)
            }
        }

        guard !assetsToAdd.isEmpty else { return }
        do {
            try await albumManager.addAssetsToAlbum(assetsToAdd, in: album)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // 找时机刷新替换：用户添加新照片后，相簿基准更新，触发刷新推荐
            await loadRecommendations(force: true)
        } catch {
            print("Failed to add picked photos: \(error)")
        }
    }

    private func loadRecommendations(force: Bool = false) async {
        // 确保相簿照片已获取
        if albumPhotos.isEmpty {
            await albumManager.fetchPhotos(in: album)
        }

        // 检查缓存：非强制刷新且存在有效缓存时直接复用，不重复触发全量扫描与骨架屏
        if !force, let cached = albumManager.getCachedRecommendations(for: album.id, currentPhotos: albumPhotos) {
            self.recommendedPhotos = cached
            self.isLoadingRecommendations = false

            // 找时机刷新替换：若缓存超过 15 分钟，后台静默刷新更新，不阻塞 UI
            if albumManager.isRecommendationCacheStale(for: album.id) {
                Task {
                    await self.performRecommendationSearch(isSilent: true)
                }
            }
            return
        }

        // 首次或强制刷新：仅在无推荐图时展示骨架
        if recommendedPhotos.isEmpty {
            isLoadingRecommendations = true
        }
        defer { isLoadingRecommendations = false }

        await performRecommendationSearch(isSilent: false)
    }

    private func performRecommendationSearch(isSilent: Bool) async {
        let albumAssets = albumPhotos.map(\.asset)
        guard !albumAssets.isEmpty else {
            if !isSilent {
                self.recommendedPhotos = []
            }
            albumManager.cacheRecommendations([], for: album.id, currentPhotos: albumPhotos)
            return
        }

        let excludingIDs = Set(albumPhotos.map(\.id))
            .union(photoManager.pendingDeletionIDs)

        do {
            let matchedAssets = try await PhotoSimilarityMatcher.shared.findSimilar(
                toAlbumAssets: albumAssets,
                excludingIDs: excludingIDs,
                topN: 30
            )
            let newPhotos = matchedAssets.map { PhotoAsset(asset: $0) }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.recommendedPhotos = newPhotos
            }
            albumManager.cacheRecommendations(newPhotos, for: album.id, currentPhotos: albumPhotos)
        } catch {
            print("Failed to find similar photos for album: \(error)")
        }
    }
}
