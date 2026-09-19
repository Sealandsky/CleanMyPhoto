import SwiftUI
import Photos
import UIKit

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
    /// 相簿上下文：从相簿页进入时提供，「更多」菜单据此展示「从相簿移除」；
    /// onRemove 由调用方执行实际移除（持有 AlbumManager）。相似照片推入的
    /// 下一级详情页不透传（素材可能不属于该相簿）
    var albumContext: (album: AlbumModel, onRemove: (PhotoAsset) -> Void)? = nil
    let onDismiss: () -> Void

    @EnvironmentObject var photoManager: PhotoManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentPhotoID: String = ""
    @State private var deleteTrigger = 0
    @State private var showFavoriteDeleteAlert = false

    // 分享状态（与原 photoBrowserView 行为一致）
    @State private var isPreparingShare = false
    @State private var shareToast: String?

    // 添加到相簿面板
    @State private var showAddToAlbum = false

    // 照片信息面板
    @State private var showInfoSheet = false

    // 大图展开（参考系统相册：单视图连续缩放，卡片 ↔ 全屏跟手无切换感）
    /// 展开进度 0~1：由 DraggablePhotoView 的展开状态机驱动（捏合逐帧/动画吸附），
    /// 页面级联动黑底淡入、其余区块淡出、禁滚动、照片区置顶
    @State private var expandProgress: CGFloat = 0
    /// 展开目标区 global frame（导航栏下安全区；恒定有效，无运行时反馈）
    @State private var expandTargetFrame: CGRect = .zero

    // 标题（地址/拍摄日期时间）
    private var captionResolver: PhotoCaptionResolver { .shared }
    @State private var captionTitle = ""
    @State private var captionSubtitle = ""

    // 相关照片（相似匹配）状态：hidden=静默（初始/出错，不渲染骨架避免
    // 白块闪现）；loading=骨架屏；loaded=结果瀑布流；empty=暂无相似
    @State private var relatedState: RelatedPhotosState = .hidden

    // 相似照片跳转：点击相似照片一律以「来源照片 + 相似列表」推入
    // 下一级详情页（原生返回逐层回退，每层独立重算标题与相似推荐）
    @State private var relatedBrowsePhotos: [PhotoAsset] = []
    @State private var relatedBrowseInitialID = ""
    @State private var isRelatedDetailActive = false

    // 本实例内删除的素材：推入页的批次是构造期快照，不随外部数据源收缩，
    // 删除后需在此即时剔除才能让大图滑向下一张；外层实例同样受益
    @State private var removedPhotoIDs: Set<String> = []

    /// 当前生效批次：剔除本实例内已删除的素材
    private var browsePhotos: [PhotoAsset] {
        photos.filter { !removedPhotoIDs.contains($0.id) }
    }

    private var currentPhoto: PhotoAsset? {
        browsePhotos.first { $0.id == currentPhotoID }
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
        albumContext: (album: AlbumModel, onRemove: (PhotoAsset) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.photos = photos
        self.initialPhotoID = initialPhotoID
        self.onDelete = onDelete
        self.onBlockedDelete = onBlockedDelete
        self.onFavoriteToggled = onFavoriteToggled
        self.onActivePhotoChange = onActivePhotoChange
        self.albumContext = albumContext
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
        Group {
            if !browsePhotos.isEmpty {
                verticalDetailLayout
            } else {
                emptyStateView
            }
        }
        // 页面底色铺满全屏（含安全区）：统一使用系统分组背景色，与设置页保持一致
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        // 操作结果反馈 toast：覆盖在详情页上，自动消失，高对比度深色胶囊，不拦截触摸
        .overlay(alignment: .bottom) {
            if let toast = shareToast {
                HStack(spacing: 8) {
                    if toast.localizedCaseInsensitiveContains("fail") || toast.contains("失败") {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    Text(toast)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color(white: 0.12).opacity(0.92))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 5)
                .padding(.bottom, 130)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shareToast)
        .navigationBarTitleDisplayMode(.inline)
        // 全屏渐隐（无位移）规则：ToolbarItem 永远存在（栏布局恒定，杜绝
        // item 移除引发的系统重排位移）——
        // · principal 标题：纯文本无玻璃容器，恒渲染 + opacity 渐隐
        // · 两个按钮：前半程 opacity 渐隐；过半换同尺寸透明占位（玻璃容器
        //   随 Button 消失，item 占位保持不变）
        // · 系统返回按钮无法控制透明度：navigationBarBackButtonHidden 常驻，
        //   改由自定义 leading 项承担（样式贴系统）
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if expandProgress < 0.5 {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(1 - expandProgress * 2)
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
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
                .opacity(max(0, 1 - expandProgress * 2))
            }
            ToolbarItem(placement: .topBarTrailing) {
                // 待处理照片入口：数量以文本实时展示，删除后立即增加
                if expandProgress < 0.5 {
                    PendingPhotosEntryButton()
                        .opacity(1 - expandProgress * 2)
                } else {
                    Color.clear.frame(width: 44, height: 36)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        // 添加到相簿：成功关闭面板后复用分享 toast 通道反馈结果
        .sheet(isPresented: $showAddToAlbum) {
            if let photo = currentPhoto {
                AddToAlbumSheet(asset: photo.asset) { albumTitle in
                    showShareToast(String(localized: "Added to \"\(albumTitle)\""))
                }
            }
        }
        // 照片信息面板
        .sheet(isPresented: $showInfoSheet) {
            if let photo = currentPhoto {
                PhotoInfoSheet(photo: photo)
            }
        }
        .alert(String(localized: "Cannot Delete"), isPresented: $showFavoriteDeleteAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "This photo is in your favorites. Remove from favorites first before deleting."))
        }
        // 相似照片点击推入的下一级详情页：系统返回/侧滑原生回退并自动
        // 复位本开关；不透传 onActivePhotoChange（层内批次索引与外部数据
        // 源无关），onDismiss 仅服务删空批次后的自动回退
        .navigationDestination(isPresented: $isRelatedDetailActive) {
            FullscreenPhotoBrowser(
                photos: relatedBrowsePhotos,
                initialPhotoID: relatedBrowseInitialID,
                onDelete: handlePhotoDeleted,
                onFavoriteToggled: onFavoriteToggled,
                onDismiss: { isRelatedDetailActive = false }
            )
            .environmentObject(photoManager)
        }
        .onAppear {
            // 初始化当前照片：优先用外部指定的初始照片，异常时回退首张
            if currentPhotoID.isEmpty || !browsePhotos.contains(where: { $0.id == currentPhotoID }) {
                currentPhotoID = browsePhotos.first(where: { $0.id == initialPhotoID })?.id
                    ?? browsePhotos.first?.id
                    ?? ""
            }
            updateCaption(for: currentPhoto)
        }
        // 标题/副标题/相关照片跟随当前素材：左右滑动切换、删除后跳转等任何
        // currentPhotoID 变化都会重启本任务（标题同步刷新；旧匹配经取消
        // 处理器自动中止，页面消失同样触发取消，防堆积与泄漏）
        .task(id: currentPhotoID) {
            updateCaption(for: currentPhoto)
            prewarmNeighbors()
            await loadRelatedPhotos()
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
    /// 操作栏布局高度（50pt 按钮 + 上下 16pt padding）
    private static let actionBarHeight: CGFloat = 82
    /// 相似照片首屏恒定露出量：卡片圆角顶部弧线，作为「下方还有内容」的滚动暗示
    private static let relatedPeekHeight: CGFloat = 48
    /// 照片区最小高度兜底（iPad 分屏等极端小可视区域）
    private static let minPhotoHeight: CGFloat = 240

    /// 顶部使用系统原生 Inline 导航栏与主副标题，其下为可滚动内容：
    /// 大图预览区域 → 缩略图条 → 操作按钮栏 → 相关图片列表推荐。
    /// 大图区高度动态填充可视区剩余空间（参考系统相册）：可视高度减去
    /// 缩略条/操作栏/首屏相似区露出量，各尺寸设备下相似卡片恒定露出一点
    private var verticalDetailLayout: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {                VStack(spacing: 0) {
                    // 大图预览区域：左右滑动切换素材，上下滑动由页面滚动接管。
                    // 视频播放与加载 loading 逻辑不变；单击进入沉浸全屏、
                    // 双指/双击缩放（缩放态禁用本页滚动）
                    DraggablePhotoView(
                        photos: browsePhotos,
                        currentPhotoID: currentPhotoID,
                        deleteTrigger: $deleteTrigger,
                        onPhotoChange: { id, index in
                            // 删除流转会在数组收缩前回报旧素材 id：此时以回退
                            // 索引对齐生效批次（索引即 DraggablePhotoView 落定
                            // 的邻近位），避免删除后当前素材悬空（标题/操作栏/
                            // 相似区失效）；正常滑动回报的 id 必在批次内
                            if browsePhotos.contains(where: { $0.id == id }) {
                                currentPhotoID = id
                            } else {
                                currentPhotoID = browsePhotos.indices.contains(index)
                                    ? browsePhotos[index].id
                                    : browsePhotos.first?.id ?? ""
                            }
                            if let photo = browsePhotos.first(where: { $0.id == currentPhotoID }) {
                                onActivePhotoChange?(photo, index)
                            }
                        },
                        onDelete: handlePhotoDeleted,
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
                        },
                        expandTargetFrame: expandTargetFrame,
                        expandProgress: $expandProgress
                    )
                    .frame(height: max(
                        Self.minPhotoHeight,
                        proxy.size.height - 8 - PhotoFilmStrip.layoutHeight
                            - Self.actionBarHeight - Self.relatedPeekHeight
                    ))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    // 展开时照片区置顶（图要盖过缩略条/操作栏铺满全屏）
                    .zIndex(expandProgress > 0.01 ? 2 : 0)

                    // 缩略图条：点击跳转直接写入 currentPhotoID（DraggablePhotoView
                    // 的 onChange 联动同步 localIndex）；同步回报索引保持外部网格
                    // 关闭详情页后的回滚定位一致
                    PhotoFilmStrip(
                        photos: browsePhotos,
                        currentPhotoID: currentPhotoID,
                        onSelect: { photo in
                            currentPhotoID = photo.id
                            if let index = browsePhotos.firstIndex(where: { $0.id == photo.id }) {
                                onActivePhotoChange?(photo, index)
                            }
                        }
                    )
                    .opacity(1 - expandProgress)
                    .allowsHitTesting(expandProgress < 0.5)

                    actionBar
                        .opacity(1 - expandProgress)
                        .allowsHitTesting(expandProgress < 0.5)
                    RelatedPhotosSection(state: relatedState, onSelect: selectRelatedAsset)
                        .opacity(1 - expandProgress)
                        .allowsHitTesting(expandProgress < 0.5)
                }
            }
            // 展开时禁用页面滚动（捏合/平移独占手势）；黑底随进度淡入
            .scrollDisabled(expandProgress > 0.01)
            .background(
                Color.black
                    .opacity(expandProgress)
                    .ignoresSafeArea()
            )
        }
        // 展开目标区 = 页面可视区 global 几何（导航栏下安全区），恒定采集
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { expandTargetFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in
                        expandTargetFrame = frame
                    }
            }
        )
    }

    /// 本实例内删除：记入删除集使生效批次即时收缩（DraggablePhotoView 依赖
    /// 数组收缩滑向下一张），并同步收敛相似推荐列表（推入页删除返回后，
    /// 父页列表不再残留已删素材），最后交还调用方执行真正的删除业务
    private func handlePhotoDeleted(_ photo: PhotoAsset) {
        removedPhotoIDs.insert(photo.id)
        if case .loaded(let assets) = relatedState {
            let remaining = assets.filter { $0.localIdentifier != photo.id }
            withAnimation(.easeInOut(duration: 0.25)) {
                relatedState = remaining.isEmpty ? .empty : .loaded(remaining)
            }
        }
        onDelete?(photo)
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

    // 「添加」：唤起相簿选择面板，把当前素材加入已有相簿或新建相簿
    private var addToAlbumButton: some View {
        glassActionButton {
            Image(systemName: "plus")
                .foregroundColor(.primary)
        } action: {
            showAddToAlbum = true
        }
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

    // 「更多」：照片信息 / 拷贝图片（仅图片类）/ 从相簿移除（仅相簿上下文）
    private var moreButton: some View {
        Menu {
            Button {
                showInfoSheet = true
            } label: {
                Label(String(localized: "Info"), systemImage: "info.circle")
            }

            if let photo = currentPhoto, photo.mediaType != .video {
                Button {
                    copyCurrentImage()
                } label: {
                    Label(String(localized: "Copy"), systemImage: "doc.on.doc")
                }
            }

            if albumContext != nil {
                Button(role: .destructive) {
                    removeFromCurrentAlbum()
                } label: {
                    Label(
                        String(localized: "Remove from Album"),
                        systemImage: "minus.circle"
                    )
                }
            }
        } label: {
            glassLabel(iconSize: 19) {
                Image(systemName: "ellipsis")
                    .foregroundColor(.primary)
            }
        }
    }

    /// 从当前相簿移除当前素材：移除业务经相簿上下文回调交还调用方执行
    /// （列表响应式收缩，本页批次随 onChange(of: photos) 自动滑向相邻素材）
    private func removeFromCurrentAlbum() {
        guard let photo = currentPhoto, let context = albumContext else { return }
        context.onRemove(photo)
        showShareToast(String(localized: "Removed from \"\(context.album.title)\""))
    }

    /// 拷贝当前图片到系统剪贴板（原始数据 + 类型），结果以 toast 反馈
    private func copyCurrentImage() {
        guard let photo = currentPhoto else { return }
        Task {
            let copied = await Self.copyImageToPasteboard(asset: photo.asset)
            showShareToast(String(localized: copied ? "Copied" : "Copy failed"))
        }
    }

    private static func copyImageToPasteboard(asset: PHAsset) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                guard let data, let uti else {
                    continuation.resume(returning: false)
                    return
                }
                UIPasteboard.general.setData(data, forPasteboardType: uti)
                continuation.resume(returning: true)
            }
        }
    }

    // 删除：沿用 deleteTrigger 触发既有删除流转（收藏拦截提示不变）；
    // 红色 tint 玻璃 + 白色图标（对齐待处理照片页「全部删除」），尺寸与收藏/分享一致
    private var deleteButton: some View {
        glassActionButton(tint: .red) {
            Image(systemName: "trash")
                .foregroundColor(.white)
        } action: {
            deleteTrigger += 1
        }
    }

    /// 系统 Liquid Glass 圆形按钮：统一在固定尺寸 frame 上叠加 glassEffect，
    /// 保证各按钮几何尺寸完全一致（默认 50pt / 19pt semibold 图标，对齐 Figma 标注）。
    /// 传入 tint 时为着色玻璃（删除等强调操作，图标需自配白色）；iOS 18 回退——
    /// 有 tint 用实色圆底，否则 ultraThinMaterial 圆形底
    @ViewBuilder
    private func glassActionButton<Content: View>(
        size: CGFloat = 50,
        iconSize: CGFloat = 19,
        tint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            glassLabel(size: size, iconSize: iconSize, tint: tint, content: content)
        }
    }

    /// 玻璃圆形样式内容（glassActionButton 与「更多」Menu label 共用，
    /// 保证按钮几何尺寸与视觉完全一致）
    @ViewBuilder
    private func glassLabel<Content: View>(
        size: CGFloat = 50,
        iconSize: CGFloat = 19,
        tint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content()
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: size, height: size)
                    .glassEffect(.regular.tint(tint).interactive(), in: Circle())
            } else {
                content()
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: size, height: size)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
        } else if let tint {
            content()
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: size, height: size)
                .background(tint, in: Circle())
        } else {
            content()
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
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
                    _ = try? handle.write(contentsOf: data)
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

    /// 预热相邻素材的数据缓存（包括地理位置地址、相似照片快照与卡片图片），
    /// 保证用户左右滑动切换到相邻照片时，卡片能瞬间（0ms）显示，彻底消除白屏与二次加载跳动。
    private func prewarmNeighbors() {
        guard let currentIndex = browsePhotos.firstIndex(where: { $0.id == currentPhotoID }) else { return }
        // 预热前后各 2 张，保证快速连续左右滑动时也能无缝命中内存缓存
        let neighborIndices = [currentIndex - 2, currentIndex - 1, currentIndex + 1, currentIndex + 2]
        let neighbors = neighborIndices.compactMap { idx in
            browsePhotos.indices.contains(idx) ? browsePhotos[idx] : nil
        }
        for neighbor in neighbors {
            PhotoCaptionResolver.shared.resolveAddress(of: neighbor.asset) { _ in }
        }
        // 1. 预热相邻素材的高清大图缓存，保证切图后迅速获得最高画质
        let highResSize = ScreenSizeHelper.screenPhysicalSize
        let neighborAssets = neighbors.map(\.asset)
        let imageOptions = PHImageRequestOptions()
        imageOptions.deliveryMode = .opportunistic
        imageOptions.isNetworkAccessAllowed = true
        imageOptions.isSynchronous = false
        PhotoAssetImageManager.shared.startCachingImages(
            for: neighborAssets,
            targetSize: highResSize,
            contentMode: .aspectFit,
            options: imageOptions
        )

        // 2. 预存相邻素材的过渡缩略图（600x600）到内存 placeholder 缓存
        // 保证左右滑动切图的第 0 毫秒立即有清晰缩略图垫底展示，随后高清大图平滑替换，彻底杜绝白屏与等待
        let thumbSize = ScreenSizeHelper.cardThumbnailSize
        for neighbor in neighbors {
            if PhotoImageCache.shared.getPlaceholder(for: neighbor.id) == nil &&
               PhotoImageCache.shared.get(for: neighbor.id, targetSize: highResSize, isHighQuality: true) == nil {
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.isNetworkAccessAllowed = true
                options.isSynchronous = false
                _ = PhotoAssetImageManager.shared.requestImage(
                    for: neighbor.asset,
                    targetSize: thumbSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, _ in
                    if let image = image {
                        PhotoImageCache.shared.setPlaceholder(
                            for: neighbor.id,
                            image: image
                        )
                    }
                }
            }
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

        // 后台全量扫描定稿：快速划动翻页时防抖 0.2s，避免连续发单引起后台队列拥堵
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else { return }

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

    // MARK: - 相似照片跳转
    /// 点击相似照片一律新开一页（不替换当前页主图，来源页上下文保持不变）：
    /// 以「来源照片 + 相似列表」推入下一级详情页，可左右连览整组相似照片；
    /// 系统返回逐层回退，每层由 .task(id:) 独立重算标题与相似推荐
    private func selectRelatedAsset(_ asset: PHAsset) {
        guard let origin = currentPhoto else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        var related: [PHAsset] = []
        if case .loaded(let assets) = relatedState { related = assets }

        // 推入批次 = 来源照片（置首，便于滑回）+ 被点目标 + 相似列表，去重
        var seen = Set<String>([origin.id])
        var deck: [PhotoAsset] = [origin]
        for candidate in [asset] + related where seen.insert(candidate.localIdentifier).inserted {
            deck.append(PhotoAsset(asset: candidate))
        }
        relatedBrowsePhotos = deck
        relatedBrowseInitialID = asset.localIdentifier
        // 种子数据先落定、推入开关下一拍再翻：同帧内同时写入目标内容与
        // 推入开关，系统会跳过推入转场（新页直接闪现而非从右侧滑入）
        Task { @MainActor in
            isRelatedDetailActive = true
        }
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
/// 以当前照片为基准的相似照片双列瀑布流（无标题，首屏仅露出顶部弧线，
/// 参考 system 相册的滚动暗示）。数据来自 PhotoSimilarityMatcher（Vision
/// 特征检索）；布局沿用占位期的版式（8pt 页边距与列距、24pt 圆角、双列错落）。
/// 单元格可点击：跳转由宿主 FullscreenPhotoBrowser 分流（批次内切换 /
/// 批次外推入下一级详情页），本模块只上报被点素材
private struct RelatedPhotosSection: View {
    let state: RelatedPhotosState
    var onSelect: (PHAsset) -> Void = { _ in }

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

    /// 统一容器：无标题版式（参考系统相册——卡片自身即区块标识，
    /// 首屏仅露出顶部弧线）；顶部 12pt 与操作栏保持呼吸间距
    private func sectionContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.top, 12)
            .padding(.bottom, 16)
    }

    /// 匹配中骨架屏：占位单元格 + 项目既有 shimmer 微光动画（不阻塞任何手势）
    private var skeletonBody: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Self.skeletonColumns.indices, id: \.self) { column in
                VStack(spacing: 8) {
                    ForEach(Self.skeletonColumns[column].indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(UIColor.secondarySystemFill))
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.skeletonColumns[column][index])
                            .shimmering(cornerRadius: 24)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    /// 结果瀑布流：双列按累计高度贪心均衡，单元格按照片原始宽高比渲染；
    /// 单元格 Button 化上报点击（按压态由 RelatedPhotoCardStyle 反馈）
    private func photoBody(_ assets: [PHAsset]) -> some View {
        let columns = Self.splitBalancedColumns(assets)
        return HStack(alignment: .top, spacing: 8) {
            ForEach(columns.indices, id: \.self) { column in
                VStack(spacing: 8) {
                    ForEach(columns[column], id: \.localIdentifier) { asset in
                        Button {
                            onSelect(asset)
                        } label: {
                            PhotoCell(
                                photo: PhotoAsset(asset: asset),
                                forceOriginalRatio: true,
                                cornerRadius: 24
                            )
                        }
                        .buttonStyle(RelatedPhotoCardStyle())
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

// MARK: - 相似照片卡片按压态
/// 轻微缩放 + 降不透明度：提示「可点」而不喧宾夺主
private struct RelatedPhotoCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}


