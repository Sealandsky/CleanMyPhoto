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

    init() {
        let storedColumns = UserDefaults.standard.integer(forKey: GridColumnHelper.columnStorageKey)
        self.columnCount = storedColumns > 0 ? storedColumns : GridColumnHelper.defaultCount

        let storedRatio = UserDefaults.standard.double(forKey: GridColumnHelper.ratioStorageKey)
        self.aspectRatio = storedRatio > 0 ? storedRatio : GridColumnHelper.defaultRatio
    }
}

enum GridColumnHelper {
    static let columnStorageKey = "gridColumnCount"
    static let ratioStorageKey = "gridAspectRatio"
    static let defaultCount = 3
    static let defaultRatio: CGFloat = 1.0
    static let spacing: CGFloat = 4

    static func columns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}
