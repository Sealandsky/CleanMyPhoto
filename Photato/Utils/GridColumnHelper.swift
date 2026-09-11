import SwiftUI

@Observable
final class GridSettings {
    var columnCount: Int {
        didSet {
            guard oldValue != columnCount else { return }
            UserDefaults.standard.set(columnCount, forKey: GridColumnHelper.columnStorageKey)
        }
    }

    var aspectRatio: CGFloat {
        didSet {
            guard oldValue != aspectRatio else { return }
            UserDefaults.standard.set(aspectRatio, forKey: GridColumnHelper.ratioStorageKey)
        }
    }

    /// 原比例模式：开启后图片列表用瀑布流按图片真实宽高比展示。
    /// 选择固定比例选项时自动关闭。
    var isOriginalRatio: Bool {
        didSet {
            guard oldValue != isOriginalRatio else { return }
            UserDefaults.standard.set(isOriginalRatio, forKey: GridColumnHelper.originalRatioStorageKey)
        }
    }

    init() {
        let storedColumns = UserDefaults.standard.integer(forKey: GridColumnHelper.columnStorageKey)
        self.columnCount = storedColumns > 0 ? storedColumns : GridColumnHelper.defaultCount

        let storedRatio = UserDefaults.standard.double(forKey: GridColumnHelper.ratioStorageKey)
        self.aspectRatio = (storedRatio >= 0.1 && storedRatio <= 2.0) ? storedRatio : GridColumnHelper.defaultRatio

        // 未设置过时默认原比例（瀑布流按图片真实宽高比）；init 赋值不触发
        // didSet，只有用户此后切换选项才落盘
        let storedOriginal = UserDefaults.standard.object(forKey: GridColumnHelper.originalRatioStorageKey) as? Bool
        self.isOriginalRatio = storedOriginal ?? true
    }
}

enum GridColumnHelper: Sendable {
    nonisolated static let columnStorageKey = "gridColumnCount"
    nonisolated static let ratioStorageKey = "gridAspectRatio"
    nonisolated static let originalRatioStorageKey = "gridIsOriginalRatio"
    /// 默认 2 列：大格更契合原比例瀑布流的浏览体验
    nonisolated static let defaultCount = 2
    nonisolated static let defaultRatio: CGFloat = 3.0 / 4.0
    nonisolated static let spacing: CGFloat = 4
    nonisolated static let horizontalPadding: CGFloat = 12 * 2
    nonisolated static let minPixelEdge: CGFloat = 260
    nonisolated static let maxPixelEdge: CGFloat = 900

    static func columns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    /// 计算指定列数下网格单元格对应的物理像素基准尺寸（正方形 targetSize + .aspectFill）
    /// 确保无论是 2 列、3 列、4 列还是瀑布流，预热与渲染的 PhotoKit targetSize 键值 100% 绝对一致
    static func thumbnailPixelSize(
        columnCount: Int,
        screenWidth: CGFloat = ScreenSizeHelper.screenSize.width,
        scale: CGFloat = ScreenSizeHelper.screenScale
    ) -> CGSize {
        let safeColumns = max(1, columnCount)
        let totalSpacing = spacing * CGFloat(safeColumns - 1)
        let cellPointWidth = (screenWidth - horizontalPadding - totalSpacing) / CGFloat(safeColumns)
        let rawPixel = cellPointWidth * scale
        let quantized = (rawPixel / 20.0).rounded(.up) * 20.0
        let edge = min(max(quantized, minPixelEdge), maxPixelEdge)
        return CGSize(width: edge, height: edge)
    }
}
