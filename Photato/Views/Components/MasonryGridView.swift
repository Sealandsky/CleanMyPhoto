import SwiftUI

// MARK: - Masonry Grid Content
/// 原比例瀑布流内容：把照片按"最短列优先"贪心分配到 N 列，每列 LazyVStack 懒加载。
///
/// 设计约束：
/// - 只输出多列内容本体，ScrollView / 坐标空间 / 手势 / 下拉刷新由页面自己提供，
///   页面原有的滚动监听、滑动多选、refreshable 等修饰符全部不受影响。
/// - 贪心分配具有前缀稳定性：分页追加新照片不会改变已有照片的列归属，
///   LazyVStack 已渲染的 cell 身份不变，不会重载。
/// - 卡片高度由 PhotoCell 内部按真实宽高比（cardAspectRatio）自动计算，
///   本组件只负责列分配，图片不拉伸、不强制裁剪变形。
struct MasonryGridContent<Content: View>: View {
    let photos: [PhotoAsset]
    let columnCount: Int
    @ViewBuilder let cell: (PhotoAsset, Int) -> Content

    init(photos: [PhotoAsset], columnCount: Int, @ViewBuilder cell: @escaping (PhotoAsset, Int) -> Content) {
        self.photos = photos
        self.columnCount = columnCount
        self.cell = cell
    }

    init(photos: [PhotoAsset], columnCount: Int, @ViewBuilder cell: @escaping (PhotoAsset) -> Content) {
        self.photos = photos
        self.columnCount = columnCount
        self.cell = { photo, _ in cell(photo) }
    }

    /// 按归一化列高（每列宽度 = 1，高度 = Σ 1/宽高比）贪心分配，并保留全局索引
    private static func computeBuckets(photos: [PhotoAsset], columnCount: Int) -> [[(photo: PhotoAsset, index: Int)]] {
        guard columnCount > 0 else { return [] }
        var columnHeights = [CGFloat](repeating: 0, count: columnCount)
        var result = [[(photo: PhotoAsset, index: Int)]](repeating: [], count: columnCount)
        for (index, photo) in photos.enumerated() {
            let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            result[shortest].append((photo, index))
            columnHeights[shortest] += 1.0 / photo.pixelAspectRatio
        }
        return result
    }

    var body: some View {
        let buckets = Self.computeBuckets(photos: photos, columnCount: columnCount)
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
/// 自适应图片网格：各图片列表页统一使用的布局容器，替换原有 LazyVGrid。
/// - 固定比例模式：LazyVGrid，行为与原实现完全一致
/// - 原比例模式（设置-显示-原比例）：瀑布流，按图片真实宽高比展示
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
        if gridSettings.isOriginalRatio {
            VStack(spacing: 0) {
                MasonryGridContent(photos: photos, columnCount: gridSettings.columnCount, cell: cell)
                footer
            }
        } else {
            LazyVGrid(columns: GridColumnHelper.columns(count: gridSettings.columnCount), spacing: GridColumnHelper.spacing) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    cell(photo, index)
                }
                footer
            }
        }
    }
}

#Preview("Masonry") {
    MasonryGridContent(photos: [], columnCount: 3) { _ in
        Color.red.frame(height: 100)
    }
}
