import SwiftUI

// MARK: - Masonry Column Assigner
/// 稳定分列管理器：
/// 1. 终身绑定：每张照片首次被加入列表后，列归属永久固定（保持稳定分列）；
/// 2. 横滑删除时：仅受影响列发生数据变动与下方上移补位，其他列照片绝对静止，彻底杜绝左右对调闪变；
/// 3. 分页追加时：新照片根据当前各列累计高度贪心分配到较矮的列，平滑自适应双列平衡；
/// 4. 切换列数或重置时：自动清理缓存并重新分配。
final class MasonryColumnAssigner {
    private var assignedColumns: [String: Int] = [:]
    private var lastColumnCount: Int = 0

    func computeBuckets(
        photos: [PhotoAsset],
        columnCount: Int,
        fixedAspectRatio: CGFloat? = nil
    ) -> [[(photo: PhotoAsset, index: Int)]] {
        guard columnCount > 0 else { return [] }

        // 列数发生变化（如在设置中由 2 列改为 3 列）时，清空缓存重新计算
        if lastColumnCount != columnCount {
            assignedColumns.removeAll()
            lastColumnCount = columnCount
        }

        // 数据源为空时重置缓存（如切换相簿或下拉刷新重抽）
        if photos.isEmpty {
            assignedColumns.removeAll()
            return Array(repeating: [], count: columnCount)
        }

        // 定期清理已不在 photos 中的过期 ID，避免缓存无限增长
        if assignedColumns.count > photos.count * 2 + 64 {
            let activeIDs = Set(photos.map(\.id))
            assignedColumns = assignedColumns.filter { activeIDs.contains($0.key) }
        }

        var columnHeights = [CGFloat](repeating: 0, count: columnCount)
        var result = [[(photo: PhotoAsset, index: Int)]](repeating: [], count: columnCount)

        for (index, photo) in photos.enumerated() {
            let itemHeight: CGFloat
            if let fixedRatio = fixedAspectRatio, fixedRatio > 0 {
                itemHeight = 1.0 / fixedRatio
            } else {
                let ratio = photo.pixelAspectRatio > 0 ? photo.pixelAspectRatio : GridColumnHelper.defaultRatio
                itemHeight = 1.0 / ratio
            }

            let targetColumn: Int
            if let cachedCol = assignedColumns[photo.id], cachedCol < columnCount {
                // 已有固定列归属：保持原有列不变！
                targetColumn = cachedCol
            } else {
                // 新照片：分配给当前累计高度最短的列
                let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
                targetColumn = shortest
                assignedColumns[photo.id] = shortest
            }

            result[targetColumn].append((photo, index))
            columnHeights[targetColumn] += itemHeight
        }

        return result
    }
}

// MARK: - Masonry Grid Content
/// 原比例瀑布流与多列网格内容：把照片按"稳定列归属 + 最短列优先"分配到 N 列，每列 LazyVStack 懒加载。
///
/// 设计约束：
/// - 只输出多列内容本体，ScrollView / 坐标空间 / 手势 / 下拉刷新由页面自己提供，
///   页面原有的滚动监听、滑动多选、refreshable 等修饰符全部不受影响。
/// - 列归属永久稳定：横滑删除某列照片时，仅该列下方照片上移补位，其他列绝对静止，杜绝左右乱窜。
/// - 分页追加具有前缀稳定性：追加新照片不会改变已有照片的列归属，已渲染 cell 身份不变。
/// - 卡片高度由 PhotoCell 内部根据宽高比（cardAspectRatio）自动撑开。
struct MasonryGridContent<Content: View>: View {
    let photos: [PhotoAsset]
    let columnCount: Int
    var fixedAspectRatio: CGFloat? = nil
    @ViewBuilder let cell: (PhotoAsset, Int) -> Content

    @State private var columnAssigner = MasonryColumnAssigner()

    init(
        photos: [PhotoAsset],
        columnCount: Int,
        fixedAspectRatio: CGFloat? = nil,
        @ViewBuilder cell: @escaping (PhotoAsset, Int) -> Content
    ) {
        self.photos = photos
        self.columnCount = columnCount
        self.fixedAspectRatio = fixedAspectRatio
        self.cell = cell
    }

    init(
        photos: [PhotoAsset],
        columnCount: Int,
        fixedAspectRatio: CGFloat? = nil,
        @ViewBuilder cell: @escaping (PhotoAsset) -> Content
    ) {
        self.photos = photos
        self.columnCount = columnCount
        self.fixedAspectRatio = fixedAspectRatio
        self.cell = { photo, _ in cell(photo) }
    }

    var body: some View {
        let buckets = columnAssigner.computeBuckets(
            photos: photos,
            columnCount: columnCount,
            fixedAspectRatio: fixedAspectRatio
        )
        HStack(alignment: .top, spacing: GridColumnHelper.spacing) {
            ForEach(0..<columnCount, id: \.self) { columnIndex in
                LazyVStack(spacing: GridColumnHelper.spacing) {
                    if columnIndex < buckets.count {
                        ForEach(buckets[columnIndex], id: \.photo.id) { item in
                            cell(item.photo, item.index)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Adaptive Photo Grid
/// 自适应图片网格：各图片列表页统一使用的布局容器。
/// - 原比例模式（设置-显示-原比例）：瀑布流，按图片真实宽高比展示
/// - 固定比例模式（1:1 / 3:4）：统一采用多列稳定布局，每列宽度与间距完全对齐
/// - 支持单列内滑动删除后下方平滑上移补位，消除跨列错位闪变
/// - 支持 (photo, index) 全局序号传递，服务滑动窗口前瞻预热
struct AdaptivePhotoGrid<Content: View, Footer: View>: View {
    let photos: [PhotoAsset]
    @ViewBuilder var cell: (PhotoAsset, Int) -> Content
    @ViewBuilder var footer: Footer

    @Environment(GridSettings.self) private var gridSettings

    /// 带全局序号初始化：无 footer
    init(photos: [PhotoAsset], @ViewBuilder cell: @escaping (PhotoAsset, Int) -> Content) where Footer == EmptyView {
        self.photos = photos
        self.cell = cell
        self.footer = EmptyView()
    }

    /// 常规初始化：无 footer（兼容单参数闭包）
    init(photos: [PhotoAsset], @ViewBuilder cell: @escaping (PhotoAsset) -> Content) where Footer == EmptyView {
        self.photos = photos
        self.cell = { photo, _ in cell(photo) }
        self.footer = EmptyView()
    }

    /// 带全局序号与 footer 初始化
    init(photos: [PhotoAsset], @ViewBuilder cell: @escaping (PhotoAsset, Int) -> Content, @ViewBuilder footer: () -> Footer) {
        self.photos = photos
        self.cell = cell
        self.footer = footer()
    }

    /// 常规初始化：带 footer（兼容单参数闭包）
    init(photos: [PhotoAsset], @ViewBuilder cell: @escaping (PhotoAsset) -> Content, @ViewBuilder footer: () -> Footer) {
        self.photos = photos
        self.cell = { photo, _ in cell(photo) }
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            MasonryGridContent(
                photos: photos,
                columnCount: gridSettings.columnCount,
                fixedAspectRatio: gridSettings.isOriginalRatio ? nil : gridSettings.aspectRatio,
                cell: cell
            )
            footer
        }
    }
}

#Preview("Masonry") {
    MasonryGridContent(photos: [], columnCount: 3) { _ in
        Color.red.frame(height: 100)
    }
}
