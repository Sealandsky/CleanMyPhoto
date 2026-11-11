import SwiftUI
import Photos
import Combine

// MARK: - On This Day Photo List View
/// 「过去的今天」二级页容器：
/// 内容区只有一块画布（OnThisDayFreeformCanvasView），列表与自由画布是同一批卡片的两种排版，
/// 切换时只发生位移 / 尺寸缩放 / 画布缩放，不替换视图、不做淡入淡出。
/// 本层负责导航栏、全屏大图、待处理入口与底部悬浮控件；
/// 已移除多选与批量删除，删除统一走卡片右上角圆形按钮或长按菜单。
struct OnThisDayPhotoListView: View {
    let group: OnThisDayYearGroup
    @ObservedObject var photoManager: PhotoManager
    /// 兼容旧调用方保留；点击卡片推入全屏大图时回调
    var onPhotoSelect: ((PhotoAsset) -> Void)? = nil
    /// 兼容旧调用方保留
    var scrollToPhotoID: String? = nil

    @State private var showFavoriteDeleteAlert = false
    @State private var canvasResetToken: Int = 0
    /// 自由画布视野已被移动/缩放过：此时才显示定位按钮，回正后隐藏
    @State private var isViewOffset: Bool = false
    /// 右上角待处理照片入口在屏幕全局坐标系中的 frame（删除动画终点）
    @State private var trashEntryFrame: CGRect = .zero
    /// 默认进入自由画布（2026-11-10 决策：入口直达散落漫游形态，网格经左下胶囊切换）
    @AppStorage("onThisDay_isCanvasMode") private var isCanvasMode: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    // MARK: 首次进入画布的操作指引贴底悬浮卡
    /// 2026-11-11 需求（参考稿）：高度严格贴合内容、不可放大。原系统 sheet 方案在
    /// iOS 26+ 存在最小高度与流式拖大行为，改为自绘卡片——不是 sheet，天然无放大通道；
    /// 挂在悬浮控件 overlay 之后，卡片直接盖住左下角切换胶囊（与原 sheet 遮挡行为一致）。
    @AppStorage("hasDismissedCanvasGuide") private var hasDismissedCanvasGuide: Bool = false
    @State private var showCanvasGuideCard: Bool = false
    /// 延迟弹卡的任务句柄：等排版切换弹簧走完再弹；中途切回网格则取消
    @State private var canvasGuideTask: Task<Void, Never>? = nil
    /// 下拉关闭的跟手位移（仅向下，不支持向上拖大）
    @State private var canvasGuideDragOffset: CGFloat = 0

    // 全屏大图（Zoom 转场）
    @State private var isFullscreenMode = false
    @State private var currentPhotoID: String? = nil
    @Namespace private var photoTransitionNamespace

    // MARK: 定位按钮「从模式切换胶囊分裂」动画
    /// iOS 26+：切换器是真 UITabBar（UIKit 控件，进不了 SwiftUI GlassEffectContainer 的
    /// glassEffectID 通道），系统级「分裂 / 融合」形变不可达（探针实测 _UITabBarAuxiliaryView
    /// 分离圆在公开 API 下渲染为隐藏）。定位按钮为等高系统玻璃圆，出现 / 消失用
    /// 「从胶囊一侧缩放滑出 / 吸回」过渡复刻分裂方向；此 spring 是过渡曲线。
    /// iOS 18 ：退回 spring + 自定义 transition。
    private static let locatorRevealAnimation: Animation =
        .spring(response: 0.42, dampingFraction: 0.76, blendDuration: 0.15)
    /// 仅 iOS 18 回退使用：锚点取按钮左边缘（紧贴切换器一侧），缩小 + 从左侧滑入 = 分裂而出；
    /// 移除时同一形变反向播放 = 吸回融合。
    private static let locatorSplitTransition: AnyTransition =
        .scale(scale: 0.3, anchor: .leading)
            .combined(with: .opacity)
            .combined(with: .move(edge: .leading))

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
    }

    /// 过滤掉已放入待删除废纸篓的素材
    private var displayedPhotos: [PhotoAsset] {
        group.photos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    var body: some View {
        OnThisDayFreeformCanvasView(
            group: group,
            photoManager: photoManager,
            isCanvasMode: isCanvasMode,
            resetToken: canvasResetToken,
            trashTarget: trashEntryFrame == .zero
                ? nil
                : CGPoint(x: trashEntryFrame.midX, y: trashEntryFrame.midY),
            onOpenPhoto: { photo in
                currentPhotoID = photo.id
                isFullscreenMode = true
                onPhotoSelect?(photo)
            },
            transitionNamespace: photoTransitionNamespace,
            onViewOffsetChange: { offset in
                // 视野偏离/回正翻转时，用 spring 驱动定位按钮的分裂弹出 / 吸回
                withAnimation(Self.locatorRevealAnimation) {
                    isViewOffset = offset
                }
            },
            onBlocked: {
                showFavoriteDeleteAlert = true
            }
        )
        .onPreferenceChange(TrashEntryFramePreferenceKey.self) { frame in
            if frame != .zero { trashEntryFrame = frame }
        }
        .onChange(of: isCanvasMode) { _, canvasMode in
            // 切换排版会复位视野，定位按钮随之吸回胶囊（带分裂形变）
            withAnimation(Self.locatorRevealAnimation) {
                isViewOffset = false
            }
            if canvasMode {
                scheduleCanvasGuideCardIfNeeded()
            } else {
                // 弹卡前的等待期内切回了网格：取消，避免卡片错弹在网格形态上
                canvasGuideTask?.cancel()
            }
        }
        .background(Color.pageBackground)
        // 标题与照片信息由画布内的回忆标题承载，导航栏不再重复显示
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 同规格（Ato msg 472）：iOS 26+ 退出系统共享玻璃底（系统胶囊带 ~4pt/侧
            // 额外内边距，38pt 内容会被撑成 ~46pt，真机实测 47.3 vs 主页 39.3），
            // 改用组件自带 38pt 标准胶囊；一层玻璃原则不变。
            // iOS 18 工具栏无玻璃底，直接用自带胶囊。
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    trashEntryButton
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    trashEntryButton
                }
            }
        }
        .dynamicSecondaryNavigationBar()
        // 全屏沉浸必须放在所有会注入 safeAreaInset 的 modifier 之后，
        // 否则画布根视图的 GeometryReader 会被重新约束成非全屏尺寸。
        .ignoresSafeArea()
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $isFullscreenMode) {
            if let photoID = currentPhotoID {
                FullscreenPhotoBrowser(
                    photos: displayedPhotos,
                    initialPhotoID: photoID,
                    onDelete: { photo in
                        photoManager.addToTrash(photo)
                    },
                    onBlockedDelete: {
                        showFavoriteDeleteAlert = true
                    },
                    onActivePhotoChange: { photo, _ in
                        currentPhotoID = photo.id
                    },
                    onDismiss: {
                        isFullscreenMode = false
                    }
                )
                .environmentObject(photoManager)
                .navigationTransition(.zoom(sourceID: photoID, in: photoTransitionNamespace))
            }
        }
        .alert(String(localized: "Cannot Delete"), isPresented: $showFavoriteDeleteAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "This photo is in your favorites. Remove from favorites first before deleting."))
        }
        .overlay(alignment: .bottomLeading) {
            // 以屏幕物理底边为基准：padding 直接挂在内容上时锚点是安全区底边，
            // 再叠 .ignoresSafeArea 会把整簇控件压到 Home Indicator 上（实测仅离物理底 ~5pt）。
            // 改用 Color.clear 先向下扩展到物理底（background 同款机制），内层 overlay 再锚定它，
            // bottomInset 从此严格等于距物理底边的距离。
            Color.clear
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottomLeading) {
                    floatingControls
                        // 胶囊居中缩放后布局框左缘内缩 ~9.5pt：leading 9 使胶囊视觉左缘
                        // 仍距屏幕左缘 ~18pt（与缩小前一致，横向位置不漂移）
                        .padding(.leading, 9)
                        .padding(.bottom, CanvasFloatingControlMetrics.bottomInset)
                }
        }
        .onAppear {
            scheduleCanvasGuideCardIfNeeded()
        }
        .onDisappear {
            // 等待期内离开页面（推入大图等）：取消，避免回来时卡片无延迟直弹
            canvasGuideTask?.cancel()
        }
        // 指引贴底悬浮卡：挂在悬浮控件 overlay 之后 → 画在切换胶囊之上（遮挡一致），
        // 底部锚定同样用 Color.clear 扩展到物理底，卡底距 Home Indicator 上方留 ~10pt。
        .overlay(alignment: .bottom) {
            Color.clear
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) {
                    if showCanvasGuideCard {
                        canvasGuideCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 44)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
        }
    }

    // MARK: - 首次进入画布的操作指引贴底悬浮卡
    /// 首次进入自由画布且从未关闭过引导时，延迟 0.55s 弹出指引卡
    /// （等「排整齐 → 散开」的形态切换弹簧先走完，卡片再升起，两个动画不打架）。
    private func scheduleCanvasGuideCardIfNeeded() {
        guard isCanvasMode, !hasDismissedCanvasGuide, !displayedPhotos.isEmpty, !showCanvasGuideCard else {
            return
        }
        canvasGuideTask?.cancel()
        canvasGuideTask = Task {
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                showCanvasGuideCard = true
            }
        }
    }

    /// 关闭即持久化：点 × 或下拉关闭后不再出现
    private func dismissCanvasGuideCard() {
        hasDismissedCanvasGuide = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showCanvasGuideCard = false
            canvasGuideDragOffset = 0
        }
    }

    /// 卡片本体：高度由内容撑起（无任何可拉伸的 detent），白底大圆角贴底悬浮；
    /// 顶部 grabber 是纯视觉元素——卡片不是 sheet，向下只有「下拉关闭」，不存在拖大。
    private var canvasGuideCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 12)

            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Roam the Free Canvas"))
                    .font(.system(size: 20, weight: .bold))
                Spacer(minLength: 16)
                Button {
                    dismissCanvasGuideCard()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close"))
            }
            .padding(.bottom, 18)

            canvasGuideRow(
                icon: "rectangle.on.rectangle",
                title: String(localized: "Switch Layouts"),
                detail: String(localized: "Tap the capsule at the bottom-left corner to switch between grid and free canvas.")
            )
            canvasGuideRow(
                icon: "hand.draw",
                title: String(localized: "Move the Canvas"),
                detail: String(localized: "Drag to roam freely, pinch to zoom.")
            )
            canvasGuideRow(
                icon: "hand.rays",
                title: String(localized: "View Photos"),
                detail: String(localized: "Tap a photo to open it, tap the corner badge to delete.")
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white)
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15),
            radius: 24,
            x: 0,
            y: 10
        )
        .offset(y: canvasGuideDragOffset)
        .gesture(canvasGuideDismissDrag)
    }

    private func canvasGuideRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.primary.opacity(0.07)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
    }

    /// 下拉关闭：仅响应向下位移（向上不跟手 = 不可拖大）；拉过阈值或快速下滑即关闭
    private var canvasGuideDismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                canvasGuideDragOffset = value.translation.height
            }
            .onEnded { value in
                let shouldDismiss = canvasGuideDragOffset > 90
                    || value.predictedEndLocation.y - value.startLocation.y > 200
                if shouldDismiss {
                    dismissCanvasGuideCard()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        canvasGuideDragOffset = 0
                    }
                }
            }
    }

    /// 回收站入口（工具栏用）：自带 38pt 标准胶囊 + 打开回收站时高亮对应照片的帧定位
    private var trashEntryButton: some View {
        PendingPhotosEntryButton(isLiquidGlass: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TrashEntryFramePreferenceKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            )
    }

    // MARK: - 左下角悬浮控件（模式切换 + 定位）
    /// 切换器为系统原生 Liquid Glass 胶囊（自然 188 × 62，2026-11-11 等比缩小到 ~169 × 56 渲染），
    /// 定位按钮为等高（56pt 直径）系统玻璃圆，两者以视觉 ~14.5pt 间隙并排——
    /// 复刻系统「搜索圆从 tab bar 分裂而出」的静态形态。
    /// 仅自由画布且视野移动/缩放过后定位按钮才出现；点击复位自动消失。
    @ViewBuilder
    private var floatingControls: some View {
        HStack(alignment: .bottom, spacing: CanvasFloatingControlMetrics.splitGap) {
            ViewModeSwitcher(isCanvasMode: $isCanvasMode)
            if isCanvasMode && isViewOffset {
                if #available(iOS 26.0, *) {
                    recenterButton
                        .glassEffect(.regular.interactive(), in: Circle())
                        // 从胶囊一侧（前缘）缩放淡入 = 分裂而出；消失反向 = 吸回
                        .transition(
                            .scale(scale: 0.5, anchor: .leading)
                                .combined(with: .opacity)
                        )
                } else {
                    recenterButton
                        .headerLiquidGlass()
                        .transition(Self.locatorSplitTransition)
                }
            }
        }
    }

    /// 定位（回正）按钮本体：iOS 26 分支在外层叠加 glassEffect（系统液态玻璃圆），
    /// iOS 18 分支叠加 headerLiquidGlass，故这里只提供图标与命中区域。
    /// 直径与缩小后的胶囊视觉等高（56pt）；符号对齐缩放后的胶囊 tab 图标量级（~25 × 0.9 ≈ 22pt）。
    private var recenterButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            canvasResetToken += 1
            withAnimation(Self.locatorRevealAnimation) {
                isViewOffset = false
            }
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.primary)
                .frame(
                    width: CanvasFloatingControlMetrics.locatorSize,
                    height: CanvasFloatingControlMetrics.locatorSize
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Recenter"))
    }

}

// MARK: - 待处理入口位置测量
/// toolbar 内容在部分系统版本上不向上传递 preference，
/// 画布侧对 nil 有几何估算兜底，见 OnThisDayFreeformCanvasView.tossOffset。
private struct TrashEntryFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
