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

    // MARK: - Private

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
