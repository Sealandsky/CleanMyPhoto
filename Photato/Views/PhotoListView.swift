import SwiftUI
import Photos

struct PhotoListView: View {
    @ObservedObject var photoManager: PhotoManager
    let onPhotoSelect: (PhotoAsset) -> Void
    var scrollToPhotoID: String? = nil
    var onScrollOffsetChanged: ((CGFloat) -> Void)? = nil

    @State private var scrollOffset: CGFloat = 0
    @State private var selectionManager = SelectionManager()
    @Environment(GridSettings.self) private var gridSettings

    // Swipe multi-select state
    @State private var cellFrames: [String: CGRect] = [:]
    @State private var isSwipeSelecting = false
    @State private var lastSwipeID: String? = nil
    @State private var autoScrollTimer: Timer?
    @State private var autoScrollDirection: AutoScrollDirection? = nil
    @State private var scrollViewHeight: CGFloat = 0
    @State private var dragIntent: DragIntent? = nil

    private enum AutoScrollDirection {
        case up, down
    }

    private enum DragIntent {
        case scroll, select
    }

    private var photos: [PhotoAsset] {
        photoManager.displayedPhotos
    }

    private var columns: [GridItem] {
        GridColumnHelper.columns(count: gridSettings.columnCount)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .top) {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(key: ScrollOffsetPreferenceKey.self,
                                        value: -geometry.frame(in: .named("scrollView")).minY)
                    }
                    .frame(height: 0)

                    LazyVGrid(columns: columns, spacing: GridColumnHelper.spacing) {
                        ForEach(photos) { photo in
                            PhotoCell(
                                photo: photo,
                                isSelected: selectionManager.isSelected(photo.id),
                                isSelectMode: selectionManager.isSelectMode
                            )
                            .id(photo.id)
                            .contentShape(Rectangle())
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            cellFrames[photo.id] = geo.frame(in: .named("scrollView"))
                                        }
                                        .onChange(of: geo.frame(in: .named("scrollView"))) { _, frame in
                                            cellFrames[photo.id] = frame
                                        }
                                }
                            )
                            .onTapGesture {
                                if selectionManager.isSelectMode {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectionManager.toggle(photo.id)
                                    }
                                } else {
                                    onPhotoSelect(photo)
                                }
                            }
                            .onLongPressGesture(minimumDuration: 0.3) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectionManager.toggle(photo.id)
                                }
                            }
                            .onAppear {
                                if photo.id == photos.last?.id {
                                    Task {
                                        await photoManager.fetchMorePhotos()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)

                    if photoManager.isLoadingMore {
                        ProgressView()
                            .foregroundColor(.white)
                            .padding()
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { scrollViewHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in scrollViewHeight = h }
                }
            )
            .background(Color.black)
            .coordinateSpace(name: "scrollView")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                scrollOffset = offset
                onScrollOffsetChanged?(offset)
            }
            .simultaneousGesture(
                selectionManager.isSelectMode ? swipeSelectGesture(proxy: proxy) : nil
            )
            .onAppear {
                if let photoID = scrollToPhotoID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withTransaction(Transaction(animation: nil)) {
                            proxy.scrollTo(photoID, anchor: .center)
                        }
                    }
                }
            }
            .onChange(of: scrollToPhotoID) { oldValue, newValue in
                guard let photoID = newValue else { return }
                let photoExists = photos.contains(where: { $0.id == photoID })
                if photoExists {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withTransaction(Transaction(animation: nil)) {
                            proxy.scrollTo(photoID, anchor: .center)
                        }
                    }
                }
            }
        }
        .onChange(of: selectionManager.isSelectMode) { _, newValue in
            photoManager.isSelectMode = newValue
        }
        .toolbar {
            if selectionManager.isSelectMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectionManager.clearSelection()
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(String(localized: "\(selectionManager.count) Selected"))
                        .font(.body.weight(.medium))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let selected = photos.filter { selectionManager.isSelected($0.id) }
                        for photo in selected {
                            photoManager.addToTrash(photo)
                        }
                        selectionManager.clearSelection()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                            Text(String(localized: "Delete"))
                        }
                    }
                    .tint(.red)
                    .disabled(selectionManager.isEmpty)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectionManager.isSelectMode)
    }

    // MARK: - Swipe Select Gesture

    private let edgeZone: CGFloat = 80

    private func swipeSelectGesture(proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("scrollView"))
            .onChanged { value in
                // Phase 1: Determine drag intent from direction
                if dragIntent == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    if dx + dy < 15 { return }
                    dragIntent = dy > dx * 1.5 ? .scroll : .select
                }
                guard dragIntent == .select else { return }

                let location = value.location

                if !isSwipeSelecting {
                    isSwipeSelecting = true
                    if let hitID = photoID(at: location) {
                        selectionManager.beginSwipe(for: hitID)
                        lastSwipeID = hitID
                    }
                }

                if let hitID = photoID(at: location), hitID != lastSwipeID {
                    selectionManager.applySwipe(hitID)
                    lastSwipeID = hitID
                }

                handleAutoScroll(location: location, proxy: proxy)
            }
            .onEnded { _ in
                isSwipeSelecting = false
                lastSwipeID = nil
                dragIntent = nil
                stopAutoScroll()
            }
    }

    // MARK: - Hit Test

    private func photoID(at point: CGPoint) -> String? {
        var bestMatch: (id: String, area: CGFloat)?
        for (id, frame) in cellFrames where frame.contains(point) {
            let area = frame.width * frame.height
            if bestMatch == nil || area < bestMatch!.area {
                bestMatch = (id, area)
            }
        }
        return bestMatch?.id
    }

    // MARK: - Auto Scroll

    private func handleAutoScroll(location: CGPoint, proxy: ScrollViewProxy) {
        guard scrollViewHeight > 0 else { return }

        if location.y < edgeZone {
            startAutoScroll(.up, proxy: proxy)
        } else if location.y > scrollViewHeight - edgeZone {
            startAutoScroll(.down, proxy: proxy)
        } else {
            stopAutoScroll()
        }
    }

    private func startAutoScroll(_ direction: AutoScrollDirection, proxy: ScrollViewProxy) {
        guard autoScrollDirection != direction else { return }
        stopAutoScroll()
        autoScrollDirection = direction

        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                let targetID: String?
                if direction == .up {
                    targetID = firstVisiblePhotoID()
                } else {
                    targetID = lastVisiblePhotoID()
                }
                guard let id = targetID else { return }

                let idx = photos.firstIndex(where: { $0.id == id }) ?? 0
                let step = gridSettings.columnCount
                let nextIdx: Int
                if direction == .up {
                    nextIdx = max(0, idx - step)
                } else {
                    nextIdx = min(photos.count - 1, idx + step)
                }
                let nextID = photos[nextIdx].id

                withTransaction(Transaction(animation: nil)) {
                    proxy.scrollTo(nextID, anchor: direction == .up ? .bottom : .top)
                }

                if isSwipeSelecting {
                    selectRange(from: id, to: nextID)
                }
            }
        }
    }

    private func selectRange(from startID: String, to endID: String) {
        guard let startIdx = photos.firstIndex(where: { $0.id == startID }),
              let endIdx = photos.firstIndex(where: { $0.id == endID }) else { return }
        let range = min(startIdx, endIdx)...max(startIdx, endIdx)
        for i in range {
            selectionManager.applySwipe(photos[i].id)
        }
        lastSwipeID = endID
    }

    private func firstVisiblePhotoID() -> String? {
        for photo in photos {
            if let frame = cellFrames[photo.id], frame.midY > 0, frame.midY < scrollViewHeight {
                return photo.id
            }
        }
        return photos.first?.id
    }

    private func lastVisiblePhotoID() -> String? {
        for photo in photos.reversed() {
            if let frame = cellFrames[photo.id], frame.midY > 0, frame.midY < scrollViewHeight {
                return photo.id
            }
        }
        return photos.last?.id
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollDirection = nil
    }
}

#Preview {
    PhotoListView(photoManager: PhotoManager()) { _ in }
}
