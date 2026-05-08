import SwiftUI

@MainActor
@Observable
final class SelectionManager {
    var selectedIDs: Set<String> = []
    private(set) var isSelectMode: Bool = false

    var count: Int { selectedIDs.count }
    var isEmpty: Bool { selectedIDs.isEmpty }

    func isSelected(_ id: String) -> Bool {
        selectedIDs.contains(id)
    }

    func enterSelectMode() {
        isSelectMode = true
    }

    func toggle(_ id: String) {
        if isSelectMode {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        } else {
            selectedIDs.insert(id)
            isSelectMode = true
        }
    }

    func clearSelection() {
        selectedIDs.removeAll()
        isSelectMode = false
    }
}
