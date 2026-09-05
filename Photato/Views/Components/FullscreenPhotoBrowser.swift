import SwiftUI
import Photos

// MARK: - Fullscreen Photo Browser
/// 详情页全屏照片浏览器（可复用组件）：由 ContentView 的 photoBrowserView
/// 提取而来，供图库/发现/相簿等数据源共用手势浏览（滑动切换、上滑删除、
/// 下滑关闭）+ 顶部返回/标题/回收站 + 底部收藏/分享/删除 + 手势引导。
///
/// 外部只注入数据与回调，组件内部自管理当前照片 ID、分享、标题、手势引导；
/// 删除/收藏的具体数据变更通过回调交还调用方（保持各数据源的业务闭环）。
struct FullscreenPhotoBrowser: View {
    let photos: [PhotoAsset]
    /// 打开时的当前照片（组件内部此后自管理）
    let initialPhotoID: String
    /// 上滑或按钮删除：调用方执行数据变更（如 addToTrash、移出发现批次）
    var onDelete: ((PhotoAsset) -> Void)? = nil
    /// 收藏照片被删除拦截时的提示回调（外部弹 alert 或其他处理）
    var onBlockedDelete: (() -> Void)? = nil
    /// 收藏切换完成回调（photo, 新的收藏状态）：用于同步发现批次等外部状态
    var onFavoriteToggled: ((PhotoAsset, Bool) -> Void)? = nil
    /// 当前照片切换回调（photo, index）：用于图库页的索引预加载等
    var onActivePhotoChange: ((PhotoAsset, Int) -> Void)? = nil
    let onDismiss: () -> Void

    @EnvironmentObject var photoManager: PhotoManager

    @State private var currentPhotoID: String = ""
    @State private var deleteTrigger = 0
    @State private var showFavoriteDeleteAlert = false

    // 分享状态（与原 photoBrowserView 行为一致）
    @State private var isPreparingShare = false
    @State private var shareToast: String?

    // 标题（地址/拍摄日期时间）
    private var captionResolver: PhotoCaptionResolver { .shared }
    @State private var captionTitle = ""
    @State private var captionSubtitle = ""

    // 相关照片（相似匹配）状态：hidden=静默（初始/出错，不渲染骨架避免
    // 白块闪现）；loading=骨架屏；loaded=结果瀑布流；empty=暂无相似
    @State private var relatedState: RelatedPhotosState = .hidden

    // 手势引导（全局只提示一次）
    @AppStorage("hasShownGestureInstructions") private var hasShownGestureInstructions: Bool = false
    @State private var showGestureInstructions = false

    private var currentPhoto: PhotoAsset? {
        photos.first { $0.id == currentPhotoID }
    }

    /// 显式构造器：当前照片在构造期即为外部指定的目标照片。
    /// 关键修复——此前 currentPhotoID 在 onAppear 才初始化，首帧渲染时为空字符串，
    /// DraggablePhotoView 回退显示列表第一张、onAppear 后才切换为目标照片，
    /// 造成"先显示第一张、再跳变"的闪烁错乱。
    init(
        photos: [PhotoAsset],
        initialPhotoID: String,
        onDelete: ((PhotoAsset) -> Void)? = nil,
        onBlockedDelete: (() -> Void)? = nil,
        onFavoriteToggled: ((PhotoAsset, Bool) -> Void)? = nil,
        onActivePhotoChange: ((PhotoAsset, Int) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.photos = photos
        self.initialPhotoID = initialPhotoID
        self.onDelete = onDelete
        self.onBlockedDelete = onBlockedDelete
        self.onFavoriteToggled = onFavoriteToggled
        self.onActivePhotoChange = onActivePhotoChange
        self.onDismiss = onDismiss

        // 目标照片不在批次中（已被删除等异常）时回退首张
        let initial = photos.first(where: { $0.id == initialPhotoID })?.id
            ?? photos.first?.id
            ?? ""
        _currentPhotoID = State(initialValue: initial)

        // 相关照片初始状态：有缓存快照时与页面首帧同在（标题+图片不后置弹出）。
        // 快照走同步内存查询（matcher 备忘命中零开销）；无缓存 → .loading 骨架
        if let baseAsset = photos.first(where: { $0.id == initial })?.asset,
           let snapshot = PhotoSimilarityMatcher.shared.cachedSnapshotSync(to: baseAsset) {
            _relatedState = State(initialValue: snapshot.isEmpty ? .empty : .loaded(snapshot))
        } else {
            _relatedState = State(initialValue: .loading)
        }
    }

    var body: some View {
        ZStack {
            Group {
                if !photos.isEmpty {
                    verticalDetailLayout
                } else {
                    emptyStateView
                }
            }

            if showGestureInstructions {
                gestureInstructionsOverlay
            }
        }
        // 页面底色铺满全屏（含安全区）：统一使用系统分组背景色，与设置页保持一致
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        // 分享结果 toast：覆盖在详情页上，自动消失，不拦截触摸
        .overlay(alignment: .bottom) {
            if let toast = shareToast {
                Text(toast)
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 130)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shareToast)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(captionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !captionSubtitle.isEmpty {
                        Text(captionSubtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: captionTitle)
                .animation(.easeInOut(duration: 0.22), value: captionSubtitle)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .alert(String(localized: "Cannot Delete"), isPresented: $showFavoriteDeleteAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "This photo is in your favorites. Remove from favorites first before deleting."))
        }
        .onAppear {
            // 初始化当前照片：优先用外部指定的初始照片，异常时回退首张
            if currentPhotoID.isEmpty || !photos.contains(where: { $0.id == currentPhotoID }) {
                currentPhotoID = photos.first(where: { $0.id == initialPhotoID })?.id
                    ?? photos.first?.id
                    ?? ""
            }
            updateCaption(for: currentPhoto)
        }
        // 标题/副标题/相关照片跟随当前素材：左右滑动切换、删除后跳转等任何
        // currentPhotoID 变化都会重启本任务（标题同步刷新；旧匹配经取消
        // 处理器自动中止，页面消失同样触发取消，防堆积与泄漏）
        .task(id: currentPhotoID) {
            updateCaption(for: currentPhoto)
            await loadRelatedPhotos()
            prewarmNeighbors()
        }
        // 照片被外部移除（删除等）时跳转到相邻照片
        .onChange(of: photos) { oldPhotos, newPhotos in
            guard !currentPhotoID.isEmpty, !newPhotos.contains(where: { $0.id == currentPhotoID }) else { return }
            if let oldIndex = oldPhotos.firstIndex(where: { $0.id == currentPhotoID }) {
                let newIndex = min(oldIndex, newPhotos.count - 1)
                currentPhotoID = newPhotos.indices.contains(newIndex) ? newPhotos[newIndex].id : newPhotos.first?.id ?? ""
            } else {
                currentPhotoID = newPhotos.first?.id ?? ""
            }
        }
    }

    // MARK: - 垂直流式版式（对齐 Figma 639-3025）
    /// 顶部使用系统原生 Inline 导航栏与主副标题，其下为可滚动内容：
    /// 大图预览区域 → 操作按钮栏 → 相关图片列表推荐
    private var verticalDetailLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // 大图预览区域：左右滑动切换素材，上下滑动由页面滚动接管。
                // 视频播放与加载 loading 逻辑不变。高度取屏幕的 55%
                DraggablePhotoView(
                    photos: photos,
                    currentPhotoID: currentPhotoID,
                    deleteTrigger: $deleteTrigger,
                    onPhotoChange: { id, index in
                        currentPhotoID = id
                        if let photo = photos.first(where: { $0.id == id }) {
                            onActivePhotoChange?(photo, index)
                        }
                    },
                    onDelete: { photo in
                        onDelete?(photo)
                    },
                    onBlockedDelete: {
                        showFavoriteDeleteAlert = true
                    },
                    onDismiss: {
                        onDismiss()
                    },
                    screenSize: ScreenSizeHelper.screenSize,
                    cardPresentation: .embeddedSection,
                    isFavorite: { photo in
                        photoManager.isFavorite(photo)
                    }
                )
                .frame(height: ScreenSizeHelper.screenSize.height * 0.55)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .onAppear {
                    showGestureInstructionsIfNeeded()
                }

                actionBar
                RelatedPhotosSection(state: relatedState)
            }
        }
    }

    // 操作按钮栏：左侧[收藏 添加 分享 更多]横向排布，右侧独立[删除]；
    // 尺寸对齐 Figma：50pt 按钮、10pt 间距、16pt 页边距、82pt 栏高（上下 16）
    private var actionBar: some View {
        HStack {
            HStack(spacing: 10) {
                favoriteButton
                addToAlbumButton
                shareButton
                moreButton
            }
            Spacer()
            deleteButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var isCurrentFavorite: Bool {
        guard let photo = currentPhoto else { return false }
        return photoManager.isFavorite(photo)
    }

    // 收藏：切换后经回调同步外部数据源状态（如发现批次）
    private var favoriteButton: some View {
        glassActionButton {
            Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                .foregroundColor(isCurrentFavorite ? .red : .primary)
                .animation(.easeInOut(duration: 0.2), value: isCurrentFavorite)
        } action: {
            if let photo = currentPhoto {
                let willBeFavorite = !isCurrentFavorite
                photoManager.toggleFavorite(photo)
                onFavoriteToggled?(photo, willBeFavorite)
            }
        }
    }

    // 「添加」：入口占位（对齐 Figma 加号按钮），加入相册等能力后续迭代接入
    private var addToAlbumButton: some View {
        glassActionButton {
            Image(systemName: "plus")
                .foregroundColor(.primary)
        } action: {}
    }

    // 分享：图片请求高清图、视频导出原文件后唤起系统分享面板
    private var shareButton: some View {
        glassActionButton {
            if isPreparingShare {
                ProgressView()
                    .tint(.primary)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.primary)
            }
        } action: {
            shareCurrentItem()
        }
        .disabled(isPreparingShare)
    }

    // 「更多」：入口占位，具体能力后续迭代接入
    private var moreButton: some View {
        glassActionButton {
            Image(systemName: "ellipsis")
                .foregroundColor(.primary)
        } action: {}
    }

    // 删除：沿用 deleteTrigger 触发既有删除流转（收藏拦截提示不变）；
    // 图标红色 #FF383C 对齐 Figma 的破坏性操作标识
    private var deleteButton: some View {
        glassActionButton {
            Image(systemName: "trash")
                .foregroundColor(Color(red: 1.0, green: 0.22, blue: 0.235))
        } action: {
            deleteTrigger += 1
        }
    }

    /// 系统 Liquid Glass 圆形按钮：iOS 26+ 使用系统 glassEffect（含触摸高亮），
    /// iOS 18 回退 ultraThinMaterial 圆形底。默认 50pt 按钮 / 19pt semibold
    /// 图标，对齐 Figma 标注；深浅色对比度由系统材质保证
    @ViewBuilder
    private func glassActionButton<Content: View>(
        size: CGFloat = 50,
        iconSize: CGFloat = 19,
        @ViewBuilder content: @escaping () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                content()
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: size, height: size)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
        } else {
            Button(action: action) {
                content()
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: size, height: size)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    // 空数据兜底：与原 emptyLibraryView 一致的占位样式（文字颜色跟随主题保证对比度）
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60, design: .rounded))
                .foregroundColor(.gray)
            Text(String(localized: "No Photos Found"))
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(String(localized: "Your photo library appears to be empty."))
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Share Current Item
    /// 分享当前素材：图片请求高清图、视频导出原文件 → 唤起系统分享面板。
    /// 只读操作，不影响收藏/删除等任何原有业务。
    private func shareCurrentItem() {
        guard let photo = currentPhoto else { return }
        isPreparingShare = true
        Task {
            // 图片/Live Photo/GIF：高清图；视频：导出原文件
            let item: Any? = photo.mediaType == .video
                ? await exportVideoFile(for: photo.asset)
                : await requestShareImage(for: photo.asset)

            isPreparingShare = false
            guard let item else {
                // 资源异常（已删除/元数据损坏/iCloud 拉取失败/导出失败）：
                // 失败 toast，不会崩溃，也不回退分享其他素材
                showShareToast(String(localized: "Share failed"))
                return
            }
            // UIKit 呈现：面板从底部弹出，默认半屏、上滑展开全屏；
            // 发起失败（无呈现上下文）时静默兜底并提示
            let presented = ShareSheetPresenter.present(items: [item]) { completed, error in
                if error != nil {
                    showShareToast(String(localized: "Share failed"))
                } else if completed {
                    showShareToast(String(localized: "Shared successfully"))
                }
                // completed=false 且无 error：用户取消，不打扰
            }
            if !presented {
                showShareToast(String(localized: "Share failed"))
            }
        }
    }

    /// 导出视频原文件到临时目录，返回分享用文件 URL。
    /// 使用 PHAssetResourceManager 流式写入（避免大视频整段载入内存）；
    /// 文件位于 temporaryDirectory，由系统按需清理
    private func exportVideoFile(for asset: PHAsset) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let resources = PHAssetResource.assetResources(for: asset)
            // 优先原尺寸视频，回退任意视频资源
            guard let videoResource = resources.first(where: { $0.type == .fullSizeVideo })
                ?? resources.first(where: { $0.type == .video }) else {
                continuation.resume(returning: nil)
                return
            }

            // 扩展名从资源的统一类型标识推断（mov/mp4/m4v）
            let ext = UTType(videoResource.uniformTypeIdentifier)?
                .preferredFilenameExtension ?? "mov"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
            FileManager.default.createFile(atPath: url.path, contents: nil)

            guard let handle = try? FileHandle(forWritingTo: url) else {
                DispatchQueue.main.async { continuation.resume(returning: nil) }
                return
            }

            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true   // iCloud 视频允许拉取原文件

            PHAssetResourceManager.default().requestData(
                for: videoResource,
                options: options,
                dataReceivedHandler: { data in
                    // 增量数据流式追加写入（非全量，控制内存峰值）
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                },
                completionHandler: { error in
                    try? handle.close()
                    DispatchQueue.main.async {
                        // 失败时清理半成品文件
                        if error != nil {
                            try? FileManager.default.removeItem(at: url)
                            continuation.resume(returning: nil)
                        } else {
                            continuation.resume(returning: url)
                        }
                    }
                }
            )
        }
    }

    /// 请求用于分享的高清图。requestImage 对同一请求可能回调多次
    /// （先降级缩略帧、后高清帧），通过 PHImageResultIsDegradedKey 过滤降级帧。
    private func requestShareImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }
                continuation.resume(returning: image)
            }
        }
    }

    /// 分享结果 toast：2.5 秒后自动消失
    private func showShareToast(_ text: String) {
        shareToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            shareToast = nil
        }
    }

    // MARK: - 标题（地址/拍摄日期时间）
    /// 标题双行规则（图片/视频同套渲染逻辑）：
    /// - 有地址：主标题=地址，副标题=完整拍摄日期+时间
    /// - 无地址：主标题=拍摄日期，副标题=拍摄时间
    /// - 拍摄日期时间元数据缺失：主、副标题置空，不渲染占位文案
    private func updateCaption(for photo: PhotoAsset?) {
        // 先同步写入本素材的日期/时间：切换素材当帧即生效，不残留上一条数据
        guard let photo,
              let date = captionResolver.shootingDate(of: photo.asset),
              let time = captionResolver.shootingTime(of: photo.asset) else {
            // 无当前素材，或拍摄日期时间元数据缺失：主、副标题置空兜底
            captionTitle = ""
            captionSubtitle = ""
            return
        }

        let cached = captionResolver.cachedAddress(of: photo.asset)
        if cached.isCached {
            // 命中缓存（含相邻素材静默预热）：直接同步赋值，切换瞬间（0ms）即展示真实地点，彻底消除延迟跳变
            if let address = cached.address, !address.isEmpty {
                captionTitle = address
                captionSubtitle = "\(date) \(time)"
            } else {
                captionTitle = date
                captionSubtitle = time
            }
        } else {
            // 未命中缓存：先以日期/时间垫底，异步完成后平滑淡入更新
            captionTitle = date
            captionSubtitle = time

            captionResolver.resolveAddress(of: photo.asset) { address in
                // 竞态守卫：快速切换素材后，迟到的地址只应用于当前素材
                guard photo.id == currentPhotoID else { return }
                // 地址缺失或为空串：维持无地址规则（日期/时间），主标题不出现空白
                guard let address, !address.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    captionTitle = address
                    captionSubtitle = "\(date) \(time)"
                }
            }
        }
    }

    /// 预热相邻素材的数据缓存（包括地理位置地址与相似照片快照），
    /// 保证用户左右滑动切换到相邻照片时，标题和相关推荐能瞬间（0ms）显示，避免出现转圈或闪烁。
    private func prewarmNeighbors() {
        guard let currentIndex = photos.firstIndex(where: { $0.id == currentPhotoID }) else { return }
        let prevIndex = currentIndex - 1
        let nextIndex = currentIndex + 1
        let neighbors = [prevIndex, nextIndex].compactMap { idx in
            photos.indices.contains(idx) ? photos[idx] : nil
        }
        for neighbor in neighbors {
            PhotoCaptionResolver.shared.resolveAddress(of: neighbor.asset) { _ in }
        }
        Task(priority: .utility) {
            for neighbor in neighbors {
                _ = await PhotoSimilarityMatcher.shared.cachedSnapshot(to: neighbor.asset)
            }
        }
    }

    // MARK: - 相关照片数据（相似匹配）
    /// 以当前照片为基准发起后台相似匹配。
    /// 计算全程在 PhotoSimilarityMatcher 的串行队列执行，主线程仅收最终状态：
    /// 不阻塞大图缩放、滑动等任何手势；任务随 .task 生命周期自动取消
    /// （切换照片/页面消失 → onCancel → matcher.cancel）
    private func loadRelatedPhotos() async {
        guard let photo = currentPhoto else {
            withAnimation(.easeInOut(duration: 0.25)) {
                relatedState = .hidden
            }
            return
        }

        let matcher = PhotoSimilarityMatcher.shared
        // 先取消可能残留的旧扫描，保证串行队列立即服务本次检索
        matcher.cancel()

        // 同步快照：init 已给出初值，此处仅刷新（如启动预热晚于首次进入导致的缺数据）
        if let snapshot = matcher.cachedSnapshotSync(to: photo.asset) {
            let newState: RelatedPhotosState = snapshot.isEmpty ? .empty : .loaded(snapshot)
            if newState != relatedState {
                withAnimation(.easeInOut(duration: 0.25)) {
                    relatedState = newState
                }
            }
        } else if case .loaded = relatedState {
            // 内存库尚未就绪且已有展示（上一张的快照不再适用）→ 亮骨架过渡
            withAnimation(.easeInOut(duration: 0.25)) {
                relatedState = .loading
            }
        }

        // 后台全量扫描定稿：有特征缓存时近乎瞬时；结果与已展示一致时跳过重写
        let result: ([PHAsset], Error?) = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                matcher.findSimilar(to: photo.asset) { assets, error in
                    continuation.resume(returning: (assets, error))
                }
            }
        } onCancel: {
            // 页面消失/素材已切换：中止后台扫描（回调 .cancelled，旧协程随即退出）
            Task { @MainActor in
                matcher.cancel()
            }
        }

        // 任务已被取代：状态由新一轮任务接管，此处不再写入（防旧结果覆盖新素材）
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            if result.1 != nil {
                // 匹配失败（权限不足/基准图不可提取/已取消）：静默隐藏列表区域，
                // 不弹窗打扰主图浏览
                relatedState = .hidden
            } else if result.0.isEmpty {
                relatedState = .empty
            } else if case .loaded(let shown) = relatedState,
                      shown.map(\.localIdentifier) == result.0.map(\.localIdentifier) {
                // 与已展示内容完全一致：跳过重写，避免列表无谓重绘闪动
            } else {
                relatedState = .loaded(result.0)
            }
        }
    }

    // MARK: - Gesture Instructions
    private func showGestureInstructionsIfNeeded() {
        if !hasShownGestureInstructions && !showGestureInstructions {
            withAnimation(.easeIn(duration: 0.3)) {
                showGestureInstructions = true
            }
        }
    }

    private var gestureInstructionsOverlay: some View {
        VStack {
            Spacer()
            // 垂直流式版式仅保留左右滑动切换，垂直手势已交还页面滚动
            VStack(spacing: 8) {
                gestureHint(icon: "arrow.left", text: String(localized: "Older"))
                gestureHint(icon: "arrow.right", text: String(localized: "Newer"))
            }
            .padding(.bottom, 120)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showGestureInstructions = false
                    hasShownGestureInstructions = true
                }
            }
        }
    }

    private func gestureHint(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(.caption, design: .rounded))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .foregroundColor(.white)
        .cornerRadius(15)
    }
}

#Preview {
    FullscreenPhotoBrowser(photos: [], initialPhotoID: "", onDismiss: {})
        .environmentObject(PhotoManager())
}

// MARK: - 相关照片模块状态
/// loading = 匹配中（骨架屏）；loaded = 结果瀑布流；empty = 暂无相似（轻量占位）；
/// hidden = 出错或无基准（静默隐藏，不弹窗打扰主图浏览）
private enum RelatedPhotosState: Equatable {
    case loading
    case loaded([PHAsset])
    case empty
    case hidden
}

// MARK: - 相关照片列表模块
/// 「More like this photo」：以当前照片为基准的相似照片双列瀑布流。
/// 数据来自 PhotoSimilarityMatcher（Vision 特征检索）；布局沿用占位期的
/// 版式（8pt 页边距与列距、24pt 圆角、双列错落）。
private struct RelatedPhotosSection: View {
    let state: RelatedPhotosState

    /// 骨架屏列高：沿用占位期错落节奏
    private static let skeletonColumns: [[CGFloat]] = [
        [152, 238, 319],
        [246, 278, 183],
    ]

    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .loading:
            sectionContent { skeletonBody }
        case .loaded(let assets):
            sectionContent { photoBody(assets) }
        case .empty:
            sectionContent { emptyBody }
        }
    }

    /// 统一容器：标题（对齐 Figma：20pt semibold）+ 内容区
    private func sectionContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "More like this photo"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 26)
                .padding(.bottom, 20)
            content()
        }
        .padding(.bottom, 16)
    }

    /// 匹配中骨架屏：占位单元格 + 项目既有 shimmer 微光动画（不阻塞任何手势）
    private var skeletonBody: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Self.skeletonColumns.indices, id: \.self) { column in
                VStack(spacing: 8) {
                    ForEach(Self.skeletonColumns[column].indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.skeletonColumns[column][index])
                            .shimmering()
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    /// 结果瀑布流：双列按累计高度贪心均衡，单元格按照片原始宽高比渲染
    private func photoBody(_ assets: [PHAsset]) -> some View {
        let columns = Self.splitBalancedColumns(assets)
        return HStack(alignment: .top, spacing: 8) {
            ForEach(columns.indices, id: \.self) { column in
                VStack(spacing: 8) {
                    ForEach(columns[column], id: \.localIdentifier) { asset in
                        AssetImage(
                            asset: asset,
                            targetSize: CGSize(width: 400, height: 400),
                            contentMode: .fill
                        )
                        .frame(maxWidth: .infinity)
                        .aspectRatio(Self.cellAspectRatio(of: asset), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    /// 空状态：轻量占位（无相似结果时不留大片空白，也不渲染完整骨架）
    private var emptyBody: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 26, design: .rounded))
                .foregroundColor(Color(.tertiaryLabel))
            Text(String(localized: "No similar photos yet"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    /// 单元格宽高比（w/h）：与 PhotoAsset.pixelAspectRatio 同规则钳制到 [1/3, 3]，
    /// 元数据异常回退默认比例，维持瀑布流视觉均衡
    private static func cellAspectRatio(of asset: PHAsset) -> CGFloat {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return GridColumnHelper.defaultRatio }
        return min(max(CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight), 1.0 / 3.0), 3.0)
    }

    /// 双列贪心均衡分配：每张追加到累计高度较矮的列
    private static func splitBalancedColumns(_ assets: [PHAsset]) -> [[PHAsset]] {
        var columns: [[PHAsset]] = [[], []]
        var heights: [CGFloat] = [0, 0]
        for asset in assets {
            let index = heights[0] <= heights[1] ? 0 : 1
            columns[index].append(asset)
            heights[index] += 1.0 / cellAspectRatio(of: asset)
        }
        return columns
    }
}


