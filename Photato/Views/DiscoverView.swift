import SwiftUI
import Photos
import Combine

// MARK: - Discover Manager
/// 发现页 ViewModel：从系统照片库随机抽取一批图片供浏览，滚动到底自动追加下一批。
/// 观察模式沿用项目主流的 ObservableObject + @Published（与 PhotoManager 一致），
/// @MainActor 保证所有状态变更都在主线程。
@MainActor
final class DiscoverManager: ObservableObject {
    /// 每批随机采样的张数（3 列 × 20 行）。相册总数不足时取全部。
    static let sampleCount = 60

    /// 当前已展示的照片批次（复用现有 PhotoAsset 模型，媒体类型徽章自动生效）
    @Published private(set) var photos: [PhotoAsset] = []
    /// 系统照片库资源总数（0 表示相册为空，View 层据此展示空状态）
    @Published private(set) var totalCount = 0
    /// 是否已完成首次加载（区分"加载中"与"相册为空"）
    @Published private(set) var hasLoadedOnce = false
    /// 刷新/加载进行中标记（统一防重入：下拉刷新与滚动加载互斥）
    @Published private(set) var isSampling = false
    /// 是否还有未展示的资源（滚到底加载用）
    @Published private(set) var hasMorePhotos = false

    /// 当前选中的媒体格式筛选器
    @Published var selectedFilter: MediaFormatFilter = .all

    // 筛选分类快照缓存：记录每个分类已加载的批次与洗牌池，避免重复切换时频繁刷新
    private struct FilterSnapshot {
        var photos: [PhotoAsset] = []
        var totalCount: Int = 0
        var hasLoadedOnce: Bool = false
        var hasMorePhotos: Bool = false
        var pool: [Int] = []
        var poolCursor: Int = 0
        var fetchResult: PHFetchResult<PHAsset>? = nil
    }

    private var filterSnapshots: [MediaFormatFilter: FilterSnapshot] = [:]

    // 惰性洗牌池：pool[poolCursor...] 为尚未展示过的资源索引。
    // 只在抽取时交换对应位置，O(每批) 而非 O(全库)；不放回抽样，跨批次不重复。
    private var pool: [Int] = []
    private var poolCursor = 0
    private var fetchResult: PHFetchResult<PHAsset>? = nil

    /// 重新随机抽取一批（下拉刷新 / 首次进入 / 某分类首次加载时调用）。
    /// .refreshable 的语义即"手指离开屏幕后才执行"，松手前不会触发本方法。
    func refresh() async {
        guard !isSampling else { return }
        isSampling = true
        defer { isSampling = false }

        let currentFilter = selectedFilter

        // 惰性获取 PHFetchResult，不将全库对象物化到字典，极大降低内存和启动耗时
        let (result, count) = await Task.detached(priority: .userInitiated) { () -> (PHFetchResult<PHAsset>, Int) in
            let options = PHFetchOptions()
            options.includeHiddenAssets = false      // 与 PhotoManager 行为一致：不展示隐藏照片
            options.includeAllBurstAssets = false    // 与 PhotoManager 行为一致：排除连拍
            if let predicate = currentFilter.predicate {
                options.predicate = predicate
            }
            let res = PHAsset.fetchAssets(with: options)
            return (res, res.count)
        }.value

        fetchResult = result
        totalCount = count
        pool = Array(0..<count)
        poolCursor = 0

        // 空相册兜底：清空列表，由 View 层展示空状态占位 UI
        guard totalCount > 0 else {
            photos = []
            hasMorePhotos = false
            hasLoadedOnce = true
            filterSnapshots[currentFilter] = FilterSnapshot(
                photos: [],
                totalCount: 0,
                hasLoadedOnce: true,
                hasMorePhotos: false,
                pool: [],
                poolCursor: 0,
                fetchResult: result
            )
            return
        }

        // 总数少于采样数量时 drawBatch 自然返回全部
        let batch = drawBatch(count: Self.sampleCount)
        photos = buildPhotoAssets(batch)
        hasMorePhotos = poolCursor < pool.count
        hasLoadedOnce = true

        // 记录当前筛选分类的批次快照
        filterSnapshots[currentFilter] = FilterSnapshot(
            photos: photos,
            totalCount: totalCount,
            hasLoadedOnce: hasLoadedOnce,
            hasMorePhotos: hasMorePhotos,
            pool: pool,
            poolCursor: poolCursor,
            fetchResult: fetchResult
        )
    }

    /// 切换格式筛选器：若该分类之前已加载过，则保留上一次批次不刷新；仅首次进入该分类时刷新
    func setFilter(_ filter: MediaFormatFilter) async {
        guard filter != selectedFilter else { return }

        // 1. 保存离开当前分类时的最新状态快照
        filterSnapshots[selectedFilter] = FilterSnapshot(
            photos: photos,
            totalCount: totalCount,
            hasLoadedOnce: hasLoadedOnce,
            hasMorePhotos: hasMorePhotos,
            pool: pool,
            poolCursor: poolCursor,
            fetchResult: fetchResult
        )

        selectedFilter = filter

        // 2. 检查目标分类是否已有加载记录
        if let snapshot = filterSnapshots[filter], snapshot.hasLoadedOnce {
            // 已加载过：直接恢复上一批次数据，不刷新
            self.photos = snapshot.photos
            self.totalCount = snapshot.totalCount
            self.hasLoadedOnce = snapshot.hasLoadedOnce
            self.hasMorePhotos = snapshot.hasMorePhotos
            self.pool = snapshot.pool
            self.poolCursor = snapshot.poolCursor
            self.fetchResult = snapshot.fetchResult
        } else {
            // 首次加载该分类：发起抽样刷新
            await refresh()
        }
    }

    /// 滚动到底部：从未展示池中再随机抽一批追加（与图库页"最后一张 onAppear 加载"方式一致）
    func loadMorePhotos() async {
        guard !isSampling, hasMorePhotos else { return }
        isSampling = true
        defer { isSampling = false }

        let batch = drawBatch(count: Self.sampleCount)
        guard !batch.isEmpty else {
            hasMorePhotos = false
            filterSnapshots[selectedFilter]?.hasMorePhotos = false
            return
        }
        let built = buildPhotoAssets(batch)
        photos += built
        hasMorePhotos = poolCursor < pool.count

        // 同步更新快照
        filterSnapshots[selectedFilter]?.photos = photos
        filterSnapshots[selectedFilter]?.hasMorePhotos = hasMorePhotos
        filterSnapshots[selectedFilter]?.poolCursor = poolCursor
    }

    /// 全屏删除后同步移出批次（同时清理所有缓存池，避免切回其他分类时仍残留已删除照片）
    func removePhoto(_ photo: PhotoAsset) {
        photos.removeAll { $0.id == photo.id }
        for key in filterSnapshots.keys {
            filterSnapshots[key]?.photos.removeAll { $0.id == photo.id }
        }
    }

    /// 全屏收藏切换后同步批次内状态
    func updateFavorite(photoID: String, isFavorite: Bool) {
        if let index = photos.firstIndex(where: { $0.id == photoID }) {
            photos[index].isFavorite = isFavorite
        }
        for key in filterSnapshots.keys {
            if let index = filterSnapshots[key]?.photos.firstIndex(where: { $0.id == photoID }) {
                filterSnapshots[key]?.photos[index].isFavorite = isFavorite
            }
        }
    }

    // MARK: Private

    /// 惰性 Fisher-Yates 洗牌：只交换本批要消费的位置即得到不放回的随机样本，
    /// 单批复杂度 O(批大小)，全库洗牌成本分摊到各批；同张照片不会重复出现
    private func drawBatch(count: Int) -> [PHAsset] {
        guard let fetchResult = fetchResult else { return [] }
        let n = min(count, pool.count - poolCursor)
        var result: [PHAsset] = []
        result.reserveCapacity(n)
        for i in poolCursor..<(poolCursor + n) {
            // 随机搭档 j 从 i 起在剩余区间取值，保证 swapAt 两个索引都合法
            let j = Int.random(in: i..<pool.count)
            pool.swapAt(i, j)
            let assetIndex = pool[i]
            if assetIndex < fetchResult.count {
                result.append(fetchResult.object(at: assetIndex))
            }
        }
        poolCursor += n
        return result
    }

    private func buildPhotoAssets(_ assets: [PHAsset]) -> [PhotoAsset] {
        assets.map { PhotoAsset(asset: $0) }
    }
}

// MARK: - Discover View
/// 发现页：随机展示一批系统照片库图片，下拉刷新重新抽取，滚动到底追加新一批。
/// 布局/圆角/间距/配色完全复用 PhotoCell + GridColumnHelper，与图库页一致。
struct DiscoverView: View {
    @ObservedObject var manager: DiscoverManager
    var onPhotoSelect: (PhotoAsset) -> Void
    /// 滚顶信号：外部递增时网格滚回顶部（如双击「重温」Tab）
    var scrollToTopSignal: Int = 0
    @EnvironmentObject var photoManager: PhotoManager

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
    /// offset 0——大标题完全展开且带平滑动画。锚点式 scrollTo 在本机
    /// 落位停在标题折叠处、重建令牌有闪动，边缘滚动是两者的正解
    @State private var scrollPosition = ScrollPosition(edge: .top)
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
                loadingView
            } else if manager.totalCount == 0 {
                emptyStateView
            } else {
                gridView
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        // 首次采样由 ContentView 切换到「发现」Tab 时触发，
        // 与相簿页懒加载策略一致；本视图以 opacity 0 常驻视图树，不能在这里用 .task，
        // 否则 app 启动即会执行全库枚举
    }

    // MARK: - Grid
    private var gridView: some View {
        ScrollView {
            // 自适应网格：固定比例 LazyVGrid / 原比例瀑布流
                AdaptivePhotoGrid(photos: manager.photos) { photo in
                    PhotoCell(photo: photo)
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
                }
                .padding(.horizontal, 12)
                // 尾部高度占位：滚动到底时最后一行不被悬浮底栏遮挡
                .padding(.bottom, 90)
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
            }
            // 自绘下拉刷新手势（与滚动共存）+ 指示器浮层
            .simultaneousGesture(pullGesture)
            .overlay(alignment: .top) { refreshIndicator }
            .scrollIndicators(.hidden)  // 隐藏滚动条
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
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.primary)
            Text(String(localized: "Loading photos..."))
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.primary)
        }
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
