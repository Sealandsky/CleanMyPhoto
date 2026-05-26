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

    // MARK: - Swipe Multi-Select

    /// The initial selection state when drag begins — used to determine select vs deselect
    var swipeInitialSelected: Bool = true

    func beginSwipe(for id: String) {
        swipeInitialSelected = !selectedIDs.contains(id)
        applySwipe(id)
    }

    func applySwipe(_ id: String) {
        if swipeInitialSelected {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }
}
