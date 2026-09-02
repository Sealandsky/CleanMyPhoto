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

        self.isOriginalRatio = UserDefaults.standard.bool(forKey: GridColumnHelper.originalRatioStorageKey)
    }
}

enum GridColumnHelper {
    static let columnStorageKey = "gridColumnCount"
    static let ratioStorageKey = "gridAspectRatio"
    static let originalRatioStorageKey = "gridIsOriginalRatio"
    static let defaultCount = 3
    static let defaultRatio: CGFloat = 3.0 / 4.0
    static let spacing: CGFloat = 4

    static func columns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}
