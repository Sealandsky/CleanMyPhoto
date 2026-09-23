import SwiftUI
import Photos
import Combine

// MARK: - Discover View
/// 发现页：随机展示一批系统照片库图片，下拉刷新重新抽取，滚动到底追加新一批。
/// 布局/圆角/间距/配色完全复用 PhotoCell + GridColumnHelper，与图库页一致。
struct DiscoverView: View {
    @ObservedObject var manager: DiscoverManager
    var onPhotoSelect: (PhotoAsset) -> Void
    /// 滚顶信号：外部递增时网格滚回顶部（如双击「重温」Tab）
    var scrollToTopSignal: Int = 0
    /// 定位到指定照片：详情页返回时传入最后浏览的照片 id，网格滚动对齐
    /// 该 cell（nil = 不定位；置位一次定位后由外部复位）
    var scrollToPhotoID: String? = nil
    /// 丝滑转场命名空间：由 ContentView 提供，实现列表与详情页无缝连续缩放
    var transitionNamespace: Namespace.ID? = nil
    @EnvironmentObject var photoManager: PhotoManager
    @Environment(GridSettings.self) private var gridSettings

    // MARK: - 自绘下拉刷新（DragGesture 驱动，替代系统 refreshable）
    /// 方案说明：系统 refreshable 的转圈会"扣住"滚动偏移，其弹簧归位在
    /// 大标题 + 整批数据替换的竞争下偶发失效（页面停在下拉位置）。
    /// 自绘方案：ScrollView 叠加 simultaneous DragGesture 直接跟踪手指，
    /// 松手（onEnded）即触发刷新；归位交给 ScrollView 原生 bounce。
    /// 注意：不使用 GeometryReader 偏移驱动——overscroll 的负偏移与滚动中
    /// 的 preference 上报在本机均不可靠，手势直读是唯一可靠探测层。
    @State private var isRefreshing = false
    /// 下拉进度（0 ~ 1.3，1 = 达到触发阈值）
    @State private var pullProgress: CGFloat = 0
    /// 已越过阈值（拉满），松手时触发刷新
    @State private var pullArmed = false
    /// 页面是否处于顶部物理零点：由 iOS 18 onScrollGeometryChange 精准检测 contentOffset
    @State private var isAtTop = true
    /// 本轮手势是否允许下拉刷新：在手势首个事件时按"当时是否在顶部"锁定。
    /// 防止从深处上滑回顶途中经过顶部、门控中途打开（此刻手指累计位移巨大，
    /// 会被误判为拉满武装，松手即触发刷新）
    @State private var gestureAllowsPull = false
    /// 是否已收到本轮手势的首个事件
    @State private var sawFirstGestureEvent = false
    /// 滚动位置（iOS 18 ScrollPosition）：双击回顶时按"边缘"滚到真正的
    /// offset 0——大标题完全展开且带平滑动画。不预设 edge: .top 避免状态刷新时强制回顶位移
    @State private var scrollPosition = ScrollPosition()
    /// 行业标准触发距离（手指滑动行程约 175pt），配合非线性阻尼曲线防误触
    private static let triggerTravelDistance: CGFloat = 175

    /// 下拉刷新手势：与滚动共存（simultaneous）。
    /// 仅"手势开始时页面就在物理顶部"且"垂直向下意图明确"的手势才可能触发下拉刷新
    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                // 手势首个事件（位移接近 0 视为新手势）时锁定门控：
                // 开始时不在物理顶部 → 整轮手势让位于正常滚动
                if !sawFirstGestureEvent || abs(value.translation.height) < 4 {
                    sawFirstGestureEvent = true
                    gestureAllowsPull = isAtTop && !isRefreshing
                }
                guard gestureAllowsPull else {
                    if pullProgress > 0 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            pullProgress = 0
                            pullArmed = false
                        }
                    }
                    return
                }
                guard !isRefreshing else { return }

                let dy = value.translation.height
                let dx = value.translation.width

                // 意图过滤与防误触：
                // 1. 必须是垂直向下位移；
                // 2. 垂直位移显著大于水平位移（斜滑过滤，角度 > 55 度）
                if dy > 0 && dy > abs(dx) * 1.4 {
                    // 阻尼处理：采用非线性幂函数模拟真实橡皮筋阻力（越往下拉越费力）
                    let normalizedProgress = dy / Self.triggerTravelDistance
                    let dampedProgress = min(1.25, pow(normalizedProgress, 0.88))
                    pullProgress = dampedProgress

                    if !pullArmed && pullProgress >= 1.0 {
                        withAnimation(.easeOut(duration: 0.12)) { pullArmed = true }
                        // 拉到阈值：段落感触觉反馈提示"松手即可刷新"
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    // 滞后解除武装：拉过后若推回阈值以下（0.75），松手不再触发
                    if pullArmed && pullProgress < 0.75 {
                        withAnimation(.easeOut(duration: 0.12)) { pullArmed = false }
                    }
                } else if dy <= 0 && pullProgress > 0 {
                    // 手指回推至起点：进度归零
                    pullProgress = 0
                    pullArmed = false
                }
            }
            .onEnded { _ in
                sawFirstGestureEvent = false
                if gestureAllowsPull && pullArmed && !isRefreshing {
                    triggerRefresh()
                } else {
                    withAnimation(.easeOut(duration: 0.25)) {
                        pullProgress = 0
                        pullArmed = false
                    }
                }
                gestureAllowsPull = false
            }
    }

    private func triggerRefresh() {
        // 触发即解除武装：若不复位，下一次任意小拖动松手都会带着
        // 残留的 armed=true 再次触发（"下拉一点点就刷新"的根因）
        pullArmed = false
        isRefreshing = true
        Task {
            await runRefresh()
            withAnimation(.easeOut(duration: 0.25)) {
                isRefreshing = false
                pullProgress = 0
                pullArmed = false
            }
        }
    }

    /// 视觉呈现进度：在拉深一定距离（pullProgress > 0.35，即手指下拉约 60pt）之前不露头；
    /// 之后才平滑滑出，到达 1.0 时正好就位
    private var visualPullProgress: CGFloat {
        if isRefreshing { return 1.0 }
        let deadZone: CGFloat = 0.35
        guard pullProgress > deadZone else { return 0 }
        return min(1.0, (pullProgress - deadZone) / (1.0 - deadZone))
    }

    // MARK: - 下拉指示器（从顶部平滑滑入，刷新完成后上移消失）
    @ViewBuilder
    private var refreshIndicator: some View {
        if isRefreshing || visualPullProgress > 0.01 {
            Group {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.primary)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(pullArmed ? .blue : .primary)
                        .rotationEffect(.degrees(visualPullProgress * 180))
                }
            }
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial, in: Circle())
            // 位置：停驻于屏幕 y ≈ 140pt（与「回忆」大标题水平带居中齐平）
            .offset(y: indicatorOffsetY)
            .opacity(isRefreshing ? 1.0 : Double(min(1, visualPullProgress * 1.5)))
            .transition(.opacity)
        }
    }

    /// 指示器纵向位置：停驻于屏幕 y ≈ 140pt 位置（介于顶部导航栏与内容卡片之间的大标题水平带）
    private var indicatorOffsetY: CGFloat {
        if isRefreshing { return -55 }
        return -120 + visualPullProgress * 65
    }

    // 权限校验：延续现有方案，直接读取 PhotoManager.authorizationStatus。
    // ContentView 外层已做权限分流，此处为防御性兜底（如权限在后台被收回）。
    private var isAuthorized: Bool {
        photoManager.authorizationStatus == .authorized || photoManager.authorizationStatus == .limited
    }

    var body: some View {
        Group {
            if !isAuthorized {
                permissionHint
            } else if !manager.hasLoadedOnce {
                skeletonGridView
            } else if manager.totalCount == 0 {
                emptyStateView
            } else {
                gridView
            }
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        // 首次采样由 ContentView 切换到「发现」Tab 时触发，
        // 与相簿页懒加载策略一致；本视图以 opacity 0 常驻视图树，不能在这里用 .task，
        // 否则 app 启动即会执行全库枚举
    }

    // MARK: - Grid
    private var gridView: some View {
        // ScrollViewReader 提供按 id 精准定位（ScrollPosition.scrollTo(id:) 对
        // LazyVGrid/瀑布流中未实例化的 cell 不可靠，proxy.scrollTo 会先实例化
        // 目标 cell 再滚动——与相簿页同一套已验证方案）
        ScrollViewReader { proxy in
            ScrollView {
            // 自适应网格：固定比例 LazyVGrid / 原比例瀑布流
                AdaptivePhotoGrid(photos: manager.photos) { photo in
                    photoCellView(photo)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            // 滚动位置绑定：支持按边缘滚到真正的顶部（offset 0）
            .scrollPosition($scrollPosition)
            // iOS 18 原生精准物理偏移检测：仅当处于最顶部（offset <= 1.0）时判定为处于顶部，
            // 彻底杜绝滑动数像素后因首图依然在视口内导致的误触
            .onScrollGeometryChange(for: Bool.self) { geometry in
                (geometry.contentOffset.y + geometry.contentInsets.top) <= 1.0
            } action: { wasAtTop, isNowAtTop in
                if wasAtTop != isNowAtTop {
                    isAtTop = isNowAtTop
                }
                if !isNowAtTop && scrollPosition.edge != nil {
                    scrollPosition = ScrollPosition()
                }
            }
            // 自绘下拉刷新手势（与滚动共存）+ 指示器浮层
            .simultaneousGesture(pullGesture)
            .overlay(alignment: .top) { refreshIndicator }
            .scrollIndicators(.hidden)  // 隐藏滚动条
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // 外部滚顶信号（双击「回忆」Tab 或外部请求）：平滑滚动回最顶部，
            // edge 滚动落位 offset 0 → 大标题完全展开，无闪动
            .onChange(of: scrollToTopSignal) { _, newValue in
                guard newValue > 0 else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    scrollPosition.scrollTo(edge: .top)
                }
            }
            // 筛选条件变化时自动回滚到顶部
            .onChange(of: manager.selectedFilter) { _, _ in
                withAnimation(.easeInOut(duration: 0.35)) {
                    scrollPosition.scrollTo(edge: .top)
                }
            }
            // 详情页返回定位：滚动对齐最后浏览的照片 cell（无动画，与相簿页一致）
            .onChange(of: scrollToPhotoID) { _, newValue in
                guard let photoID = newValue else { return }
                let photoExists = manager.photos.contains(where: { $0.id == photoID })
                if photoExists {
                    // 立即定位（无延迟）：请求多来自详情页切图（网格被遮盖，
                    // 静默就位无闪跳）；ScrollPosition(id:) 直接赋值走已有绑定
                    withTransaction(Transaction(animation: nil)) {
                        scrollPosition = ScrollPosition(id: photoID, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Photo Cell View
    @ViewBuilder
    private func photoCellView(_ photo: PhotoAsset) -> some View {
        let cell = PhotoCell(photo: photo)
            .id(photo.id)
            .contentShape(Rectangle())
            .onTapGesture {
                // 交由 ContentView 打开全屏详情（复用 DraggablePhotoView）
                onPhotoSelect(photo)
            }
            .onAppear {
                // 与图库页相同：滚到最后一张时加载下一批
                if photo.id == manager.photos.last?.id {
                    Task { await manager.loadMorePhotos() }
                }
            }

        if let transitionNamespace {
            cell.matchedTransitionSource(id: photo.id, in: transitionNamespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            cell
        }
    }

    // MARK: - 下拉刷新（含最小时长保障）
    /// 补足最小刷新时长（0.6s），让自绘转圈完整呈现后再收尾
    private func runRefresh() async {
        let start = Date()
        await manager.refresh()

        let elapsed = Date().timeIntervalSince(start)
        if elapsed < Self.minRefreshDuration {
            try? await Task.sleep(nanoseconds: UInt64((Self.minRefreshDuration - elapsed) * 1_000_000_000))
        }
    }

    private static let minRefreshDuration: Double = 0.6

    // MARK: - Empty State
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: manager.selectedFilter == .all ? "photo.on.rectangle.angled" : manager.selectedFilter.systemImage)
                    .font(.system(size: 60, design: .rounded))
                    .foregroundColor(.gray)

                Text(String(localized: "No Photos Found"))
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(manager.selectedFilter == .all ? String(localized: "Your photo library appears to be empty.") : String(localized: "No media found for the selected format."))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: UIScreen.main.bounds.height * 0.7)
        }
        // 空状态下拉刷新：同一套手势与指示器（内容不满屏，哨兵恒可见=恒在顶部）
        .simultaneousGesture(pullGesture)
        .overlay(alignment: .top) { refreshIndicator }
        .scrollIndicators(.hidden)  // 隐藏滚动条
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    // MARK: - Skeleton Loading Grid
    /// 骨架屏占位网格：在首批照片采样完成前提供与真实网格完全一致的骨架卡片流光动画，
    /// 消除白屏等待与转菊花焦虑感，列数、圆角与间距与当前设置 100% 对齐。
    private var skeletonGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: GridColumnHelper.columns(count: gridSettings.columnCount),
                spacing: GridColumnHelper.spacing
            ) {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(UIColor.secondarySystemFill))
                        .aspectRatio(gridSettings.isOriginalRatio ? 3.0 / 4.0 : gridSettings.aspectRatio, contentMode: .fit)
                        .shimmering()
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    // MARK: - Permission Hint
    private var permissionHint: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 80, design: .rounded))
                .foregroundColor(.blue)

            Text(String(localized: "Photo Access Required"))
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(String(localized: "Photato needs access to your photo library to help you organize and clean up unwanted photos."))
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}

#Preview {
    DiscoverView(manager: DiscoverManager(), onPhotoSelect: { _ in })
        .environment(GridSettings())
        .environmentObject(PhotoManager())
}
