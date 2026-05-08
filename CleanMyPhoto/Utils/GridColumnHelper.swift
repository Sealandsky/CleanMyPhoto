import SwiftUI

@Observable
final class GridSettings {
    var columnCount: Int {
        didSet {
            guard oldValue != columnCount else { return }
            UserDefaults.standard.set(columnCount, forKey: GridColumnHelper.storageKey)
        }
    }

    init() {
        let stored = UserDefaults.standard.integer(forKey: GridColumnHelper.storageKey)
        self.columnCount = stored > 0 ? stored : GridColumnHelper.defaultCount
    }
}

enum GridColumnHelper {
    static let storageKey = "gridColumnCount"
    static let defaultCount = 3
    static let spacing: CGFloat = 4

    static func columns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}
