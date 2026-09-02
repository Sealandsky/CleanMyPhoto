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
    /// 顶部回收站按钮点击（nil 时隐藏该按钮）
    var onOpenTrash: (() -> Void)? = nil
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
        onOpenTrash: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.photos = photos
        self.initialPhotoID = initialPhotoID
        self.onDelete = onDelete
        self.onBlockedDelete = onBlockedDelete
        self.onFavoriteToggled = onFavoriteToggled
        self.onActivePhotoChange = onActivePhotoChange
        self.onOpenTrash = onOpenTrash
        self.onDismiss = onDismiss

        // 目标照片不在批次中（已被删除等异常）时回退首张
        let initial = photos.first(where: { $0.id == initialPhotoID })?.id
            ?? photos.first?.id
            ?? ""
        _currentPhotoID = State(initialValue: initial)
    }

    var body: some View {
        ZStack {
            Group {
                if !photos.isEmpty {
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
                        screenSize: ScreenSizeHelper.screenSize
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        showGestureInstructionsIfNeeded()
                    }
                } else {
                    // 空数据兜底：与原 emptyLibraryView 一致的占位样式
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60, design: .rounded))
                            .foregroundColor(.gray)
                        Text(String(localized: "No Photos Found"))
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text(String(localized: "Your photo library appears to be empty."))
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
            // 图片内容充满全屏（含安全区）；顶部/底部操作栏保持在安全区内，
            // 避开状态栏与 Home Indicator——与原 photoBrowserView 布局一致
            .ignoresSafeArea()

            if showGestureInstructions {
                gestureInstructionsOverlay
            }

            VStack {
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(.title3, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .background(.ultraThinMaterial, in: Circle())

                    // 标题组：主标题=地址（无定位时为拍摄日期）；副标题=拍摄日期+时间
                    // （无定位时为拍摄时间）。超长地址单行截断，避免布局溢出
                    VStack(spacing: 2) {
                        Text(captionTitle)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(captionSubtitle)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)

                    Spacer()

                    if onOpenTrash != nil {
                        Button {
                            onOpenTrash?()
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(.title3, design: .rounded))
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)
                        }
                        .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                HStack(spacing: 16) {
                    Spacer()

                    // 收藏：切换后经回调同步外部数据源状态（如发现批次）
                    Button {
                        if let photo = currentPhoto {
                            photoManager.toggleFavorite(photo)
                            onFavoriteToggled?(photo, !photo.isFavorite)
                        }
                    } label: {
                        Image(systemName: (currentPhoto?.isFavorite ?? false) ? "heart.fill" : "heart")
                            .font(.system(.title3, design: .rounded))
                            .foregroundColor((currentPhoto?.isFavorite ?? false) ? .red : .primary)
                            .frame(width: 60, height: 60)
                    }
                    .background(.ultraThinMaterial, in: Circle())

                    // 分享按钮：点击异步请求当前图片高清图后唤起系统分享面板。
                    // 仅图片类媒体显示（视频分享需导出原文件，不在本次范围）
                    if currentPhoto?.mediaType != .video {
                        Button {
                            shareCurrentPhoto()
                        } label: {
                            Group {
                                if isPreparingShare {
                                    ProgressView()
                                        .tint(.primary)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(.title3, design: .rounded))
                                        .foregroundColor(.primary)
                                }
                            }
                            .frame(width: 60, height: 60)
                        }
                        .background(.ultraThinMaterial, in: Circle())
                        .disabled(isPreparingShare)
                    }

                    Button {
                        deleteTrigger += 1
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(.title3, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(width: 60, height: 60)
                    }
                    .background(.ultraThinMaterial, in: Circle())

                    Spacer()
                }
                .padding(.bottom, 8)
            }

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

    // MARK: - Share Current Photo
    /// 分享当前照片：异步请求高清图 → 唤起原生系统分享面板（底部弹出）。
    /// 只读操作，不影响收藏/删除等任何原有业务。
    private func shareCurrentPhoto() {
        guard let photo = currentPhoto else { return }
        isPreparingShare = true
        Task {
            // 图片资源异常（asset 已被删除/元数据损坏/iCloud 拉取失败）时
            // 返回 nil，此处给出失败 toast，不会崩溃
            let image = await requestShareImage(for: photo.asset)
            isPreparingShare = false
            guard let image else {
                showShareToast(String(localized: "Share failed"))
                return
            }
            // UIKit 呈现：面板从底部弹出，默认半屏、上滑展开全屏；
            // 发起失败（无呈现上下文）时静默兜底并提示
            let presented = ShareSheetPresenter.present(items: [image]) { completed, error in
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
    /// 标题展示规则：
    /// - 有地址：主标题=地址，副标题=拍摄日期+拍摄时间
    /// - 无地址：主标题=拍摄日期，副标题=拍摄时间
    /// - 元数据缺失：占位文案兜底，不出现空白
    private func updateCaption(for photo: PhotoAsset?) {
        guard let photo else {
            captionTitle = String(localized: "Unknown date")
            captionSubtitle = String(localized: "Unknown time")
            return
        }
        captionTitle = captionResolver.shootingDate(of: photo.asset)
        captionSubtitle = captionResolver.shootingTime(of: photo.asset)

        captionResolver.resolveAddress(of: photo.asset) { (address: String?) in
            // 竞态守卫：快速切换图片后，迟到的地址只应用于当前照片
            guard photo.id == currentPhotoID, let address else { return }
            captionTitle = address
            captionSubtitle = "\(captionResolver.shootingDate(of: photo.asset)) \(captionResolver.shootingTime(of: photo.asset))"
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
            VStack(spacing: 8) {
                gestureHint(icon: "arrow.left", text: String(localized: "Older"))
                gestureHint(icon: "arrow.right", text: String(localized: "Newer"))
                gestureHint(icon: "arrow.down", text: String(localized: "Swipe down to close"))
                gestureHint(icon: "arrow.up", text: String(localized: "Swipe up to delete"))
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
