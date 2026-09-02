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
    @ViewBuilder let cell: (PhotoAsset) -> Content

    /// 按归一化列高（每列宽度 = 1，高度 = Σ 1/宽高比）贪心分配
    private var buckets: [[PhotoAsset]] {
        var columnHeights = [CGFloat](repeating: 0, count: columnCount)
        var result = [[PhotoAsset]](repeating: [], count: columnCount)
        for photo in photos {
            let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            result[shortest].append(photo)
            columnHeights[shortest] += 1.0 / photo.pixelAspectRatio
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: GridColumnHelper.spacing) {
            ForEach(0..<columnCount, id: \.self) { columnIndex in
                LazyVStack(spacing: GridColumnHelper.spacing) {
                    ForEach(buckets[columnIndex]) { photo in
                        cell(photo)
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
///
/// cell 闭包内容与原 ForEach 内的 cell 写法完全相同（含手势、分页 onAppear 等），
/// 页面从 LazyVGrid 迁移到本组件只需替换外层容器，cell 定义零改动。
struct AdaptivePhotoGrid<Content: View, Footer: View>: View {
    let photos: [PhotoAsset]
    @ViewBuilder var cell: (PhotoAsset) -> Content
    @ViewBuilder var footer: Footer

    @Environment(GridSettings.self) private var gridSettings

    /// 常规初始化：无 footer
    init(photos: [PhotoAsset], @ViewBuilder cell: @escaping (PhotoAsset) -> Content) where Footer == EmptyView {
        self.photos = photos
        self.cell = cell
        self.footer = EmptyView()
    }

    /// 带 footer 初始化：分页加载指示器等追加内容
    /// （固定比例下作为网格最后一个 item；瀑布流下铺满整行放在列内容之后）
    init(photos: [PhotoAsset], @ViewBuilder cell: @escaping (PhotoAsset) -> Content, @ViewBuilder footer: () -> Footer) {
        self.photos = photos
        self.cell = cell
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
                ForEach(photos) { photo in
                    cell(photo)
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
