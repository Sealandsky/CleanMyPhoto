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
    /// 滚顶信号：外部递增时网格滚回顶部（如再次点击「重温」Tab）
    var scrollToTopSignal: Int = 0
    @EnvironmentObject var photoManager: PhotoManager

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
        .background(Color.black)
        // 首次采样由 ContentView 切换到「发现」Tab 时触发（topSegmentedControl.onChange），
        // 与相簿页懒加载策略一致；本视图以 opacity 0 常驻视图树，不能在这里用 .task，
        // 否则 app 启动即会执行全库枚举
    }

    // MARK: - Grid
    private var gridView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // 顶部归位锚点：下拉刷新完成后显式滚回此处，
                // 规避 SwiftUI refreshable 偶发的"页面停在下拉位置不回弹"缺陷
                Color.clear
                    .frame(height: 0)
                    .id(DiscoverView.topAnchorID)

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
            }
            // 下拉刷新：refreshable 在手指释放后才执行（松手前不会触发采样），
            // 刷新期间显示系统转圈；重新抽取一批全新的图片替换当前批次
            .refreshable {
                await runRefresh()
                // 刷新完成后强制归位（带回弹动画），
                // 双保险规避 refreshable 回弹动画丢失的问题
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(DiscoverView.topAnchorID, anchor: .top)
                }
            }
            // 外部滚顶信号：平滑滚回顶部锚点
            .onChange(of: scrollToTopSignal) { _, newValue in
                guard newValue > 0 else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(DiscoverView.topAnchorID, anchor: .top)
                }
            }
        }
    }

    // MARK: - 下拉刷新（含最小时长保障）
    /// SwiftUI 已知缺陷：refreshable 闭包极快返回时（本地采样仅几十毫秒），
    /// 数据替换会与 ScrollView 的回弹动画竞争，偶发导致页面（含大标题）
    /// 停在被下拉的位置不回弹。
    /// 规避方式：补足最小刷新时长（0.6s），让系统转圈先完整呈现、
    /// 数据稳定后闭包再返回，回弹动画即可正常执行。
    private func runRefresh() async {
        let start = Date()
        await manager.refresh()

        let elapsed = Date().timeIntervalSince(start)
        if elapsed < Self.minRefreshDuration {
            try? await Task.sleep(nanoseconds: UInt64((Self.minRefreshDuration - elapsed) * 1_000_000_000))
        }
    }

    private static let minRefreshDuration: Double = 0.6
    /// 网格顶部归位锚点 id（下拉刷新后强制滚回）
    private static let topAnchorID = "discover_top_anchor"

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
                    .foregroundColor(.white)

                Text(String(localized: "Your photo library appears to be empty."))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: UIScreen.main.bounds.height * 0.7)
        }
        // 空状态下保留下拉刷新：用户在系统相册添加照片后可直接下拉重试
        .refreshable {
            await runRefresh()
        }
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text(String(localized: "Loading photos..."))
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white)
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
