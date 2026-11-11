import SwiftUI
import Photos
import UIKit

// MARK: - 回忆画布（同一批卡片，散落 / 整齐两种排版）
/// 列表与自由画布始终是同一块画布上的**同一批卡片实体**：
/// 切换只是把卡片从螺旋散落的位置「位移」到标题下方的整齐网格（以及反向），
/// 倾斜角与点击交互两种排版完全一致，不替换视图、不使用任何淡入淡出转场。
/// 轻量交互：轻点看大图、右上角 badge 删除、长按弹出菜单。
struct OnThisDayFreeformCanvasView: View {
    let group: OnThisDayYearGroup
    @ObservedObject var photoManager: PhotoManager
    var isCanvasMode: Bool = false
    var resetToken: Int = 0
    /// 右上角「待处理照片」入口中心（屏幕全局坐标），删除动画的终点
    var trashTarget: CGPoint? = nil
    /// 轻点卡片：由容器推入全屏大图浏览器
    var onOpenPhoto: ((PhotoAsset) -> Void)? = nil
    /// Zoom 转场的配对命名空间（与容器的 navigationTransition 共用）
    let transitionNamespace: Namespace.ID
    /// 视野偏离初始位置时通知容器显示定位按钮；回正后通知隐藏
    var onViewOffsetChange: ((Bool) -> Void)? = nil
    let onBlocked: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(GridSettings.self) private var gridSettings

    // 缩放与平移手势状态
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @GestureState private var gestureZoom: CGFloat = 1.0
    @GestureState private var gesturePan: CGSize = .zero

    /// 唯一数据源：卡片尺寸 / 原图比例 / 倾斜角 / 散落位置都在这里定死，切换时不重建卡片。
    /// 只存与视口无关的元数据；网格位置/缩放是视口的纯函数，在画布内按实时视口派生，
    /// 不再缓存到 @State，避免"首次布局视口异常 → 位置被永久算错"。
    @State private var photoLayouts: [CanvasPhotoLayout] = []
    @State private var totalSizeText: String = ""

    // 抛入待处理动画与撤销状态
    @State private var tossingPhotoIDs: Set<String> = []
    @State private var lastTrashedPhoto: PhotoAsset? = nil
    @State private var showUndoToast: Bool = false
    @State private var undoDismissTimer: Task<Void, Never>? = nil
    /// 惯性动画的会话号：复位 / 切换排版 / 新手势结束时递增，用于丢弃过期的减速动画
    @State private var inertiaSession: Int = 0
    /// 上一次上报给容器的「视野已偏离」状态，避免拖拽每帧都刷新容器
    @State private var lastReportedViewOffset: Bool = false

    /// 网格形态画布正好收窄到屏幕宽度；切到自由画布时整体放大
    private let gridBaseScale: CGFloat = 1.0
    private let canvasBaseScale: CGFloat = 1.12
    private let gridPadding: CGFloat = 8
    private let gridSpacing: CGFloat = 4
    private let gridHeaderHeight: CGFloat = 104
    /// 卡片解码尺寸固定，切换排版时不会因 targetSize 变化重新请求图片
    private let cardImageTargetSize = CGSize(width: 400, height: 400)
    /// 卡片外观常量（两种排版共用，切换时绝不变化）
    private let cardCornerRadius: CGFloat = 18
    private let cardBorderWidth: CGFloat = 3.0
    /// 排版切换唯一的动画曲线：位移量大、带一点回弹，让「排整齐」看得见
    private let modeAnimation = Animation.spring(response: 0.68, dampingFraction: 0.78)

    // MARK: - 滑动缓冲参数
    /// 松手速度（pt/s）折算成继续滑行距离时的等效时长
    private let momentumProjectionTime: CGFloat = 0.15
    /// 单次惯性滑行上限，避免猛甩一下飞出内容区
    private let momentumMaxDistance: CGFloat = 760
    /// 越界橡皮筋的参考尺寸（越大越软）
    private let rubberBandDimension: CGFloat = 390
    /// 自由画布宽松软边界 = 视口长边 × 该倍数：正常浏览碰不到，只有连续猛甩才触发回弹
    private let canvasSoftBoundary: CGFloat = 1.2

    private var effectiveScale: CGFloat {
        isCanvasMode
            ? canvasBaseScale * max(0.55, min(2.3, zoomScale * gestureZoom))
            : gridBaseScale
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: panOffset.width + gesturePan.width,
            height: panOffset.height + gesturePan.height
        )
    }

    /// 恒定数组：不随 isCanvasMode 切换数据源，ForEach 不会插入/移除视图 → 无隐式淡入淡出
    private var visibleLayouts: [CanvasPhotoLayout] {
        photoLayouts.filter { layout in
            !photoManager.pendingDeletionIDs.contains(layout.id) || tossingPhotoIDs.contains(layout.id)
        }
    }

    /// 卡片的当前位置：散落 or 整齐，尺寸与外观始终不变
    private func currentPosition(for layout: CanvasPhotoLayout, in positions: [String: CGPoint]) -> CGPoint {
        isCanvasMode ? layout.position : (positions[layout.id] ?? layout.position)
    }

    var body: some View {
        // 画布 = 整个屏幕。
        //
        // 【第四次修复·为什么彻底不再用 GeometryReader】
        // 本视图作为 navigationDestination 的根，串接 .dynamicSecondaryNavigationBar()
        //（内部 .safeAreaInset(edge:.top)）与外层 .ignoresSafeArea()。这套组合下 GeometryProxy
        // 返回的坐标系不可信：画布内一切都围绕一个被压小的 frame 计算，照片被挤到屏幕中部一小簇
        //（截图实测：网格形态照片只剩 y≈467pt 一条窄带，画布形态照片仅在 y≈550pt 露出一角），
        // 而画布背景、右上回收站、左下切换器因各自 ignoresSafeArea 或相对父容器布局仍是全屏——
        // 这正是"满屏背景 + 中间一小块照片"的由来。前三次只改"视口数字"无效，因为根因是
        // GeometryProxy 这个坐标系本身，而不是传进去的尺寸值。
        //
        // 正解：画布根节点不再嵌 GeometryReader，改用一个确定性占满全屏的 ZStack（.frame 固定为
        // 主屏尺寸 + .ignoresSafeArea），让所有子视图的坐标系就是这个全屏 frame 的中心。卡片与标题
        // 的位置全部相对这个中心计算，绝不依赖 GeometryProxy。canvasOrigin 传 .zero（全屏画布原点
        // 即屏幕左上角），删除动画终点 trashTarget 本身是 global 坐标，正好与之一致。
        let viewport = screenViewportSize()
        ZStack {
            // 1. 画布底板背景
            canvasBackgroundColor

            if visibleLayouts.isEmpty {
                allDoneEmptyView
            } else {
                canvasContent(
                    viewportSize: viewport,
                    canvasOrigin: .zero,
                    topInset: resolvedTopInset()
                )
            }

            // 2. 底部可撤销操作浮条 (Undo Toast)
            if showUndoToast {
                VStack {
                    Spacer()
                    undoToastView
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .safeAreaPadding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 画布外框 = 主屏尺寸，且忽略安全区铺满整个屏幕。全屏坐标系的锚点（中心）由此确定，
        // 卡片 .offset 全部相对这个中心，不再受任何 GeometryProxy 的小几何影响。
        .frame(width: viewport.width, height: viewport.height)
        .ignoresSafeArea()
        .onAppear {
            setupLayouts()
            calculateSize()
        }
        .onChange(of: group.photos.count) { _, _ in
            setupLayouts()
            calculateSize()
        }
        .onChange(of: resetToken) { _, _ in
            // 定位按钮：视野平滑回到中心标题 / 网格回到顶部
            resetToCenter()
        }
        .onChange(of: isCanvasMode) { _, _ in
            // 丢掉尚未执行的惯性动画，避免它覆盖形态切换后的复位
            inertiaSession += 1
            // 清掉上一形态的平移与缩放，与卡片位移共用同一条弹簧曲线
            withAnimation(modeAnimation) {
                panOffset = .zero
                zoomScale = 1.0
            }
            reportViewOffset()
        }
    }

    /// 顶部安全区（状态栏 + 导航栏）高度：决定列表形态标题落点、删除动画右上角估算点。
    /// 画布根已不再嵌 GeometryReader，直接读当前 keyWindow 的 safeAreaInsets.top。
    /// Swift 6 严格并发下用 nonisolated + MainActor.assumeIsolated 访问 UIApplication.shared。
    private nonisolated func resolvedTopInset() -> CGFloat {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .safeAreaInsets.top ?? 59
        }
    }

    /// 画布视口尺寸 = 主屏尺寸。画布要占满整个屏幕，尺寸只由屏幕决定。
    /// 不再读 GeometryProxy：本视图作为导航二级页根，GeometryProxy 在转场期会返回
    /// 居中的小几何（详见 body 注释），是"照片被框在正中一小块"的真正来源。
    private nonisolated func screenViewportSize() -> CGSize {
        let s = MainActor.assumeIsolated { UIScreen.main.bounds.size }
        if s.width.isFinite, s.height.isFinite, s.width > 0, s.height > 0 {
            return s
        }
        return CGSize(width: 393, height: 852)
    }

    // MARK: - 布局初始化（只生成与视口无关的散落元数据；网格位置在画布内按实时视口派生）
    private func setupLayouts() {
        photoLayouts = FreeformCanvasLayoutEngine.generateLayout(photos: group.photos)
    }

    /// 整齐排版：所有卡片缩放到同一个「外接尺寸」（各自原图宽高比不变），
    /// 倾斜角也不归零，只重新计算中心点；行距额外留出倾斜后外接矩形的空间。
    private func makeGridPositions(
        layouts: [CanvasPhotoLayout],
        viewportSize: CGSize,
        topInset: CGFloat
    ) -> (positions: [String: CGPoint], scales: [String: CGFloat], scrollLimit: CGFloat) {
        let width = viewportSize.width
        let height = viewportSize.height
        let scale = gridBaseScale
        let columns = max(2, gridSettings.columnCount)
        let columnWidth = (width - gridPadding * 2 - gridSpacing * CGFloat(columns - 1)) / CGFloat(columns)
        // 最大倾斜 ±6.5°，旋转后外接矩形约膨胀 11%；0.86 系数保证仍落在列内
        let tileSide = columnWidth * 0.86
        let rowStride = tileSide + 18

        var scales: [String: CGFloat] = [:]
        scales.reserveCapacity(layouts.count)
        for layout in layouts {
            scales[layout.id] = tileSide / max(layout.size.width, layout.size.height)
        }

        // 标题区从状态栏 + 导航栏下方开始
        let headerTop = topInset + 44 + 12
        var rowTop = headerTop + gridHeaderHeight + 10
        var positions: [String: CGPoint] = [:]
        positions.reserveCapacity(layouts.count)

        var index = 0
        while index < layouts.count {
            let row = layouts[index..<min(index + columns, layouts.count)]
            for (column, layout) in row.enumerated() {
                let visualX = gridPadding + columnWidth / 2 + CGFloat(column) * (columnWidth + gridSpacing)
                let visualY = rowTop + rowStride / 2
                positions[layout.id] = CGPoint(
                    x: (visualX - width / 2) / scale,
                    y: (visualY - height / 2) / scale
                )
            }
            rowTop += rowStride
            index += columns
        }

        // 底部留出模式切换胶囊的空间
        let contentBottom = rowTop + 88
        // panOffset 作用在缩放之后，是纯屏幕点位移，不再除以 scale
        return (positions, scales, max(0, contentBottom - height))
    }

    /// 卡片显示尺寸：自由画布用原始尺寸，整齐排版统一缩放到同一外接框（比例不变）
    private func cardSize(for layout: CanvasPhotoLayout, in scales: [String: CGFloat]) -> CGSize {
        guard !isCanvasMode, let factor = scales[layout.id] else { return layout.size }
        return CGSize(width: layout.size.width * factor, height: layout.size.height * factor)
    }

    // MARK: - 画布背景色
    private var canvasBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.09)
            : Color(red: 0.96, green: 0.956, blue: 0.941)
    }

    // MARK: - 画布内容（同一块标题 + 同一批卡片）
    private func canvasContent(
        viewportSize: CGSize,
        canvasOrigin: CGPoint,
        topInset: CGFloat
    ) -> some View {
        // 每次 body 求值都按当前视口派生网格（纯函数，无时序缓存），
        // 从根上杜绝「首次布局视口异常 → 位置被永久算错」。
        let grid = makeGridPositions(layouts: photoLayouts, viewportSize: viewportSize, topInset: topInset)

        return ZStack {
            memoryHeader(viewportSize: viewportSize, topInset: topInset)

            ForEach(visibleLayouts) { layout in
                let isTossed = tossingPhotoIDs.contains(layout.id)
                let position = currentPosition(for: layout, in: grid.positions)
                // 倾斜角两种排版共用：列表只是把分散的卡片排整齐，不摆正
                let angle = layout.rotationAngle
                let toss = tossOffset(
                    position: position,
                    viewportSize: viewportSize,
                    canvasOrigin: canvasOrigin,
                    topInset: topInset
                )

                cardView(layout: layout, size: cardSize(for: layout, in: grid.scales))
                    .rotationEffect(isTossed ? Angle(degrees: angle.degrees + 45) : angle)
                    .scaleEffect(isTossed ? 0.12 : 1.0)
                    .offset(
                        x: position.x + (isTossed ? toss.width : 0),
                        y: position.y + (isTossed ? toss.height : 0)
                    )
                    .opacity(isTossed ? 0.0 : 1.0)
                    // 不在这里挂 .animation(value:)：它会屏蔽父级的排版切换动画。
                    // 删除动效改由 moveToPendingPhotos 里的显式 withAnimation 驱动。
                    // matchedTransitionSource 暂时移除：iOS 26 上与二级页 Zoom 转场组合会触发渲染异常，
                    // 卡片图层被过渡系统接管成屏幕中央一小窗（真机+模拟器均可复现，见 msg 454）。
                    // 恢复大图 Zoom 转场前需先在真机验证此修饰符。
                    // contextMenu 已按 2026-11-11 需求移除（屏蔽长按）：轻点开大图、角标删除已覆盖
                    // 同样的两个操作，长按菜单只会额外扣押触控流、干扰画布拖拽跟手。
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        // 先缩放内容、再整体平移：panOffset 是纯屏幕点位移，不会被 scaleEffect 二次放大
        .scaleEffect(effectiveScale, anchor: .center)
        .offset(effectiveOffset)
        // 排版切换的唯一动画源：卡片位置/角度、标题位置与画布缩放一起过渡，没有视图替换
        .animation(modeAnimation, value: isCanvasMode)
        .contentShape(Rectangle())
        // highPriorityGesture（2026-11-11 修复）：卡片自带 Button 与 .contextMenu，
        // 普通的 .gesture 会被子视图认领触控流——从照片上起手拖拽时画布不跟手，
        // 松手才收到一次全量 translation 导致「闪跳到手指位置」（模拟器探针复现：
        // 慢速拖拽中途画布纹丝不动，松手瞬间跳变 53% 像素）。
        // 提升优先级后：位移超过 minimumDistance(8pt) 画布手势优先接管（跟手漫游）；
        // 不移动的轻点仍归卡片按钮、长按仍归 contextMenu，互不影响。
        .highPriorityGesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .updating($gestureZoom) { value, state, _ in
                        state = isCanvasMode ? value : 1.0
                    }
                    .onEnded { value in
                        guard isCanvasMode else { return }
                        zoomScale = max(0.55, min(2.3, zoomScale * value))
                        reportViewOffset()
                    },
                DragGesture(minimumDistance: 8)
                    .updating($gesturePan) { value, state, _ in
                        // 跟手阶段就把越界位移按渐进阻尼压缩，而不是硬生生停住
                        state = dragPresentation(
                            translation: value.translation,
                            viewportSize: viewportSize,
                            gridScrollLimit: grid.scrollLimit
                        )
                    }
                    .onEnded { value in
                        endDrag(value, viewportSize: viewportSize, gridScrollLimit: grid.scrollLimit)
                    }
            )
        )
        .onTapGesture(count: 2) {
            resetToCenter()
        }
    }

    // MARK: - 定位按钮显隐（移动过视图才出现，回正后消失）
    /// 只有布尔值翻转时才通知容器，拖拽/惯性过程中不会反复刷新外层视图
    private func reportViewOffset() {
        let isOffset = abs(panOffset.width) > 2
            || abs(panOffset.height) > 2
            || abs(zoomScale - 1.0) > 0.01
        guard isOffset != lastReportedViewOffset else { return }
        lastReportedViewOffset = isOffset
        onViewOffsetChange?(isOffset)
    }

    // MARK: - 滑动缓冲（跟手橡皮筋 + 松手惯性减速 / 越界回弹）
    /// UIScrollView 风格渐进阻尼：越往外拉越拉不动，且位移始终有上限
    private func rubberBand(_ overshoot: CGFloat) -> CGFloat {
        guard overshoot > 0 else { return 0 }
        let c: CGFloat = 0.55
        return (c * overshoot * rubberBandDimension) / (rubberBandDimension + c * overshoot)
    }

    /// 把超出 ±limit 的部分按橡皮筋压缩，范围内原样返回
    private func damped(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let bounded = min(limit, max(-limit, value))
        let overshoot = value - bounded
        return bounded + (overshoot > 0 ? rubberBand(overshoot) : -rubberBand(-overshoot))
    }

    /// 跟手阶段应呈现的平移增量（相对 panOffset）：两种排版共用同一套阻尼
    private func dragPresentation(translation: CGSize, viewportSize: CGSize, gridScrollLimit: CGFloat) -> CGSize {
        let rawX = panOffset.width + translation.width
        let rawY = panOffset.height + translation.height
        if isCanvasMode {
            let limit = max(viewportSize.width, viewportSize.height) * canvasSoftBoundary
            return CGSize(
                width: damped(rawX, limit: limit) - panOffset.width,
                height: damped(rawY, limit: limit) - panOffset.height
            )
        }
        // 网格排版只允许垂直滚动，横向一律归零
        let boundedY = min(0, max(-gridScrollLimit, rawY))
        let overshoot = rawY - boundedY
        let displayedY = boundedY + (overshoot > 0 ? rubberBand(overshoot) : -rubberBand(-overshoot))
        return CGSize(width: -panOffset.width, height: displayedY - panOffset.height)
    }

    /// 松手速度 → 继续滑行的距离；限幅避免一次猛甩飞得看不见照片
    private func projectedDistance(for velocity: CGFloat) -> CGFloat {
        min(momentumMaxDistance, max(-momentumMaxDistance, velocity * momentumProjectionTime))
    }

    /// 滑得越快，减速过程越长（末端始终是 easeOut 的缓慢收尾）
    private func decelerationDuration(distance: CGFloat) -> Double {
        min(0.95, max(0.32, 0.32 + Double(distance) / 1400.0))
    }

    /// 手势结束：先无动画定格跟手位置以抵消 @GestureState 归零，
    /// 下一帧再用减速曲线滑到惯性终点；撞到边界时改用弹簧回弹。
    private func endDrag(_ value: DragGesture.Value, viewportSize: CGSize, gridScrollLimit: CGFloat) {
        let presentation = dragPresentation(
            translation: value.translation,
            viewportSize: viewportSize,
            gridScrollLimit: gridScrollLimit
        )
        panOffset = CGSize(
            width: panOffset.width + presentation.width,
            height: panOffset.height + presentation.height
        )
        reportViewOffset()

        let velocity = value.velocity
        let inertia = CGSize(
            width: isCanvasMode ? projectedDistance(for: velocity.width) : 0,
            height: projectedDistance(for: velocity.height)
        )
        let proposed = CGSize(
            width: panOffset.width + inertia.width,
            height: panOffset.height + inertia.height
        )

        let bounded: CGSize
        if isCanvasMode {
            let limit = max(viewportSize.width, viewportSize.height) * canvasSoftBoundary
            bounded = CGSize(
                width: min(limit, max(-limit, proposed.width)),
                height: min(limit, max(-limit, proposed.height))
            )
        } else {
            bounded = CGSize(width: 0, height: min(0, max(-gridScrollLimit, proposed.height)))
        }

        let hitsBoundary = abs(proposed.width - bounded.width) > 0.5
            || abs(proposed.height - bounded.height) > 0.5
        let target = hitsBoundary ? bounded : proposed
        let distance = sqrt(inertia.width * inertia.width + inertia.height * inertia.height)
        let animation: Animation = hitsBoundary
            ? .spring(response: 0.5, dampingFraction: 0.82)
            : .easeOut(duration: decelerationDuration(distance: distance))

        inertiaSession += 1
        let session = inertiaSession
        // 必须推迟一帧：否则 withAnimation 会从「拖拽前」的 panOffset 起插值，
        // 配合 gesturePan 瞬间归零会先回跳一下，再冲向终点。
        DispatchQueue.main.async {
            guard self.inertiaSession == session else { return }
            withAnimation(animation) {
                self.panOffset = target
            }
            // 惯性终点可能刚好落在中心，需按最终位置再校准一次按钮显隐
            self.reportViewOffset()
        }
    }

    // MARK: - 删除动画：精确飞向右上角待处理照片入口
    /// 卡片中心的屏幕位置 = 画布原点 + 画布中心 + panOffset + scale × (当前位置 + 抛飞位移)。
    /// 反解出让卡片中心落到入口中心的位移。toolbar 的 preference 在部分系统版本不上传，
    /// 此时按导航栏右上角入口的常规中心（右边距 34pt、导航栏中线）估算。
    private func tossOffset(
        position: CGPoint,
        viewportSize: CGSize,
        canvasOrigin: CGPoint,
        topInset: CGFloat
    ) -> CGSize {
        let scale = effectiveScale
        let target = trashTarget ?? CGPoint(
            x: canvasOrigin.x + viewportSize.width - 34,
            y: canvasOrigin.y + topInset + 22
        )
        let local = CGPoint(x: target.x - canvasOrigin.x, y: target.y - canvasOrigin.y)
        let targetX = (local.x - viewportSize.width / 2 - effectiveOffset.width) / scale
        let targetY = (local.y - viewportSize.height / 2 - effectiveOffset.height) / scale
        return CGSize(width: targetX - position.x, height: targetY - position.y)
    }

    // MARK: - 复位视野（定位按钮与双击共用）
    private func resetToCenter() {
        inertiaSession += 1
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            zoomScale = 1.0
            panOffset = .zero
        }
        reportViewOffset()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - 卡片（结构恒定，不随排版切换分支）
    /// 两个 Button 平级放在 ZStack 里：轻点卡面看大图、轻点右上角深色毛玻璃 × 角标删除，
    /// 互不嵌套，避免子父手势抢焦点；外层再挂长按菜单与 Zoom 转场源。
    private func cardView(layout: CanvasPhotoLayout, size: CGSize) -> some View {
        // 删除角标：深色毛玻璃圆底 + 白色 ×，跨压在卡片右上角
        let badgeSize: CGFloat = 28
        return ZStack(alignment: .topTrailing) {
            Button {
                onOpenPhoto?(layout.photo)
            } label: {
                polaroidCard(layout: layout, size: size)
            }
            .buttonStyle(.plain)

            Button {
                moveToPendingPhotos(layout.photo)
            } label: {
                ZStack {
                    // 系统超薄材质 + 半透明黑压暗：保留照片背景的毛玻璃模糊质感，又是深色底
                    Circle()
                        .fill(.ultraThinMaterial)
                    Circle()
                        .fill(Color.black.opacity(0.48))
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: badgeSize, height: badgeSize)
                .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            // 约 1/3 露出卡片边界之外，形成角标跨压效果（画布不裁剪，允许溢出）
            .offset(x: badgeSize * 0.35, y: -badgeSize * 0.35)
            .accessibilityLabel(String(localized: "Add to Pending Photos"))
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - 单张相纸拟物卡片（全幅等比铺满，宽高比与自由画布完全一致）
    private func polaroidCard(layout: CanvasPhotoLayout, size: CGSize) -> some View {
        return AssetImage(
            asset: layout.photo.asset,
            targetSize: cardImageTargetSize,
            contentMode: .fill,
            placeholderColor: Color(UIColor.secondarySystemFill)
        )
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.22) : Color.white,
                    lineWidth: cardBorderWidth
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1),
            radius: 6,
            x: 0,
            y: 5
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.16),
            radius: 24,
            x: 0,
            y: 22
        )
        // 视频角标：与网格 PhotoCell 同款（play.fill + 时长，黑底白字），
        // 放左下角（右上角已被删除角标占用），置于投影之后避免角标再叠投影
        .overlay(alignment: .bottomLeading) {
            if layout.photo.isVideo {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, design: .rounded))
                    if let duration = layout.photo.videoDuration {
                        Text(duration)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(6)
            }
        }
    }

    // MARK: - 回忆标题（同一块标题，只做顶部 ↔ 屏幕正中的位移）
    private func memoryHeader(viewportSize: CGSize, topInset: CGFloat) -> some View {
        let headerTop = topInset + 44 + 12
        // 自由画布形态标题钉在世界原点（画布中心），用户捏合缩放时视觉上仍居中
        let offsetY: CGFloat = isCanvasMode
            ? 0
            : (headerTop + gridHeaderHeight / 2 - viewportSize.height / 2) / gridBaseScale
        let headerWidth = (viewportSize.width - gridPadding * 2) / gridBaseScale

        return VStack(spacing: 6) {
            Text(String(localized: "On This Day"))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formattedDateText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(String(group.year))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Text(memorySubtitleText)

                if let location = group.locationName, !location.isEmpty {
                    Text("·")
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11, weight: .semibold))
                        Text(location)
                    }
                }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .frame(width: headerWidth, alignment: .center)
        .offset(y: offsetY)
        .allowsHitTesting(false)
    }

    // MARK: - 删除交互（右上角 badge / 长按菜单，两种排版完全一致）
    private func moveToPendingPhotos(_ photo: PhotoAsset) {
        // 若为已收藏照片，阻断并弹出原有提示
        if photoManager.isFavorite(photo) {
            onBlocked()
            return
        }

        // 触觉与音效反馈
        SoundManager.playSwipeDelete()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // 触发飞向右上角待处理入口的动效（显式动画，不影响排版切换的弹簧事务）
        withAnimation(.interpolatingSpring(stiffness: 180, damping: 20)) {
            _ = tossingPhotoIDs.insert(photo.id)
        }

        // 延迟入站并弹出撤销浮条
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            photoManager.addToTrash(photo)
            lastTrashedPhoto = photo

            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showUndoToast = true
            }

            undoDismissTimer?.cancel()
            undoDismissTimer = Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showUndoToast = false
                        }
                    }
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            tossingPhotoIDs.remove(photo.id)
        }
    }

    // MARK: - 撤销逻辑
    private func undoLastTrash() {
        guard let photo = lastTrashedPhoto else { return }
        undoDismissTimer?.cancel()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        photoManager.restoreFromTrash(photo.id)
        lastTrashedPhoto = nil

        withAnimation(.easeInOut(duration: 0.2)) {
            showUndoToast = false
        }
    }

    // MARK: - 首次进入画布的操作指引贴底悬浮卡
    /// 2026-11-11 需求（参考稿）：高度严格贴合内容、不可放大。原系统 sheet 方案在
    /// iOS 26+ 有最小高度与流式拖大行为，故整体移至容器层 OnThisDayPhotoListView 自绘。

    private var memorySubtitleText: String {
        let countText = String(format: String(localized: "%lld photos"), visibleLayouts.count)
        if totalSizeText.isEmpty {
            return countText
        } else {
            return "\(countText) · \(totalSizeText)"
        }
    }

    private func calculateSize() {
        totalSizeText = SizeCache.load("onthisday_\(group.id)") ?? ""
        let assets = group.photos.map(\.asset)
        Task {
            let totalSize = await Task.detached(priority: .utility) {
                await PHAssetSizeHelper.calculateTotalSize(for: assets)
            }.value
            SizeCache.save("onthisday_\(group.id)", size: totalSize)
            let newText = ByteFormatter.format(totalSize)
            if newText != totalSizeText {
                await MainActor.run {
                    totalSizeText = newText
                }
            }
        }
    }

    private var formattedDateText: String {
        let date = group.photos.first?.asset.creationDate ?? Date()
        if group.isMonthFallback {
            return date.formatted(.dateTime.month())
        } else {
            return date.formatted(.dateTime.month().day())
        }
    }

    // MARK: - 底部撤销 Toast 浮条
    private var undoToastView: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 24))

            Text(String(localized: "Moved to Pending Photos"))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Spacer()

            Button {
                undoLastTrash()
            } label: {
                Text(String(localized: "Undo"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 16, y: 6)
    }

    // MARK: - 今日照片全部移入空态
    private var allDoneEmptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, design: .rounded))
                .foregroundColor(Color.accentColor)

            Text(String(localized: "All Done for Today"))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(.primary)

            Text(String(localized: "All photos have been moved to Pending Photos."))
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
