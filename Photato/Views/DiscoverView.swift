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

    // 惰性洗牌池：pool[poolCursor...] 为尚未展示过的资源 id。
    // 只在抽取时交换对应位置，O(每批) 而非 O(全库)；不放回抽样，跨批次不重复。
    private var pool: [String] = []
    private var poolCursor = 0
    private var idToAsset: [String: PHAsset] = [:]

    /// 重新随机抽取一批（下拉刷新 / 首次进入共用）。
    /// .refreshable 的语义即"手指离开屏幕后才执行"，松手前不会触发本方法。
    func refresh() async {
        guard !isSampling else { return }
        isSampling = true
        defer { isSampling = false }

        // 后台线程枚举全库：惰性 fetchResult → 轻量 id 映射，不物化图片数据。
        // 每次刷新都重建快照，同步会话期间被删除的照片。
        let (assetMap, count) = await Task.detached(priority: .userInitiated) { () -> ([String: PHAsset], Int) in
            let options = PHFetchOptions()
            options.includeHiddenAssets = false      // 与 PhotoManager 行为一致：不展示隐藏照片
            options.includeAllBurstAssets = false    // 与 PhotoManager 行为一致：排除连拍
            let result = PHAsset.fetchAssets(with: options)
            var map: [String: PHAsset] = [:]
            map.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                map[asset.localIdentifier] = asset
            }
            return (map, result.count)
        }.value

        idToAsset = assetMap
        totalCount = count
        pool = Array(assetMap.keys)
        poolCursor = 0

        // 空相册兜底：清空列表，由 View 层展示空状态占位 UI
        guard totalCount > 0 else {
            photos = []
            hasMorePhotos = false
            hasLoadedOnce = true
            return
        }

        // 总数少于采样数量时 drawBatch 自然返回全部
        let batch = drawBatch(count: Self.sampleCount)
        photos = await buildPhotoAssets(batch)
        hasMorePhotos = poolCursor < pool.count
        hasLoadedOnce = true
    }

    /// 滚动到底部：从未展示池中再随机抽一批追加（与图库页"最后一张 onAppear 加载"方式一致）
    func loadMorePhotos() async {
        guard !isSampling, hasMorePhotos else { return }
        isSampling = true
        defer { isSampling = false }

        let batch = drawBatch(count: Self.sampleCount)
        guard !batch.isEmpty else {
            hasMorePhotos = false
            return
        }
        let built = await buildPhotoAssets(batch)
        photos += built
        hasMorePhotos = poolCursor < pool.count
    }

    /// 全屏删除后同步移出批次（DraggablePhotoView 依赖外部数组收缩以滑动到下一张，
    /// 与 Library 页 addToTrash 后 displayedPhotos 更新是同一模式）
    func removePhoto(_ photo: PhotoAsset) {
        photos.removeAll { $0.id == photo.id }
    }

    /// 全屏收藏切换后同步批次内状态，保证返回网格/再次进入时心形角标一致
    func updateFavorite(photoID: String, isFavorite: Bool) {
        if let index = photos.firstIndex(where: { $0.id == photoID }) {
            photos[index].isFavorite = isFavorite
        }
    }

    // MARK: Private

    /// 惰性 Fisher-Yates 洗牌：只交换本批要消费的位置即得到不放回的随机样本，
    /// 单批复杂度 O(批大小)，全库洗牌成本分摊到各批；同张照片不会重复出现
    private func drawBatch(count: Int) -> [PHAsset] {
        let n = min(count, pool.count - poolCursor)
        var result: [PHAsset] = []
        result.reserveCapacity(n)
        for i in poolCursor..<(poolCursor + n) {
            // 随机搭档 j 从 i 起在剩余区间取值，保证 swapAt 两个索引都合法
            let j = Int.random(in: i..<pool.count)
            pool.swapAt(i, j)
            if let asset = idToAsset[pool[i]] {
                result.append(asset)
            }
        }
        poolCursor += n
        return result
    }

    /// PhotoAsset 构建含 GIF 资源检测（PHAssetResource 调用），放后台线程避免卡主线程
    private func buildPhotoAssets(_ assets: [PHAsset]) async -> [PhotoAsset] {
        await Task.detached(priority: .userInitiated) {
            assets.map { PhotoAsset(asset: $0) }
        }.value
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
    /// 页面是否处于顶部区域：由懒容器内首个 cell 的 onAppear/onDisappear 驱动
    /// （与分页加载同机制；非懒内容的 appear 不随滚动触发，不可用）
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
    private static let refreshThreshold: CGFloat = 80

    /// 下拉刷新手势：与滚动共存（simultaneous）。
    /// 仅"手势开始时页面就在顶部"的一次手势才可能触发下拉刷新
    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                // 手势首个事件（位移接近 0 视为新手势）时锁定门控：
                // 开始时不在顶部 → 整轮手势让位于正常滚动
                if !sawFirstGestureEvent || abs(value.translation.height) < 3 {
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
                if dy > 0 {
                    // 进度 = 手指下拉距离 / 阈值（跟随手指实时增减）
                    pullProgress = min(1.3, CGFloat(dy) / Self.refreshThreshold)
                    if !pullArmed && pullProgress >= 1 {
                        withAnimation(.easeOut(duration: 0.12)) { pullArmed = true }
                        // 拉到阈值：震动反馈提示"松手即可刷新"
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    // 滞后解除武装：拉过后又推回阈值以下（0.7），
                    // 松手不再触发（对齐系统"回到阈值内即取消"的行为）
                    if pullArmed && pullProgress < 0.7 {
                        withAnimation(.easeOut(duration: 0.12)) { pullArmed = false }
                    }
                } else if pullProgress > 0 {
                    // 手指回推至起点：进度清零
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

    // MARK: - 下拉指示器（从屏幕顶部跟手滑入，刷新完成后上移消失）
    @ViewBuilder
    private var refreshIndicator: some View {
        if isRefreshing || pullProgress > 0.02 {
            Group {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.primary)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(pullArmed ? .blue : .primary)
                }
            }
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial, in: Circle())
            // 位置：下拉时从顶部上方跟手滑入，刷新中停驻，完成后上移淡出
            .offset(y: indicatorOffsetY)
            .opacity(Double(min(1, pullProgress * 1.6)))
            .transition(.opacity)
        }
    }

    /// 指示器纵向位置：progress 0 → 隐藏在顶部上方（-58），1 → 就位（+10）；
    /// 刷新中固定停驻在 +10
    private var indicatorOffsetY: CGFloat {
        if isRefreshing { return 10 }
        return -58 + min(pullProgress, 1) * 68
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
        .background(Color(UIColor.systemBackground))
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
                            // 首个 cell 可见 ⇔ 页面处于顶部区域：
                            // 懒容器内 cell 的 appear/disappear 按视口可见性触发
                            // （与下方分页加载同机制，真机验证可靠）
                            if photo.id == manager.photos.first?.id {
                                isAtTop = true
                            }
                            // 与图库页相同：滚到最后一张时加载下一批
                            if photo.id == manager.photos.last?.id {
                                Task { await manager.loadMorePhotos() }
                            }
                        }
                        .onDisappear {
                            if photo.id == manager.photos.first?.id {
                                isAtTop = false
                            }
                        }
                }
                .padding(.horizontal, 12)
            }
            // 滚动位置绑定：支持按边缘滚到真正的顶部（offset 0）
            .scrollPosition($scrollPosition)
            // 自绘下拉刷新手势（与滚动共存）+ 指示器浮层
            .simultaneousGesture(pullGesture)
            .overlay(alignment: .top) { refreshIndicator }
            .scrollIndicators(.hidden)  // 隐藏滚动条
            // 外部滚顶信号（双击「重温」Tab）：平滑滚动回最顶部，
            // edge 滚动落位 offset 0 → 大标题完全展开，无闪动
            .onChange(of: scrollToTopSignal) { _, newValue in
                guard newValue > 0 else { return }
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
