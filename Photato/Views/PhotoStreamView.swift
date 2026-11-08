import SwiftUI
import Photos

// MARK: - Photo Date Section Model
struct PhotoDateSection: Identifiable {
    let id: String
    let title: String
    let photos: [PhotoAsset]
}

// MARK: - Photo Stream View
/// 现代全量图片流视图（适用于「所有照片」与「时光归档月份相册」）：
/// 1. 支持 2 列 / 3 列 / 4 列自由切换（默认 3 列标准紧凑浸润）；
/// 2. 38pt 高度吸顶日期段（ultraThinMaterial 毛玻璃底板）；
/// 3. 单手交互：PhotoCell -> matchedTransitionSource -> swipeToTrash；
/// 4. 点击照片无缝 Zoom 放大进入 FullscreenPhotoBrowser；
/// 5. 右上角「选择」按钮支持滑动多选与批量放入废纸篓。
struct PhotoStreamView: View {
    let streamTitle: String
    var subtitle: String? = nil
    var initialPhotos: [PhotoAsset] = []
    var fetchPhotos: (() async -> [PhotoAsset])? = nil

    @ObservedObject var photoManager: PhotoManager

    @State private var localPhotos: [PhotoAsset] = []
    @State private var isLoading = false
    @State private var streamColumnCount: Int = 3
    @State private var selectionManager = SelectionManager()
    @State private var isFullscreenMode = false
    @State private var currentPhotoID: String? = nil
    @State private var canSelectPhoto = true
    @State private var showFavoriteDeleteAlert = false
    @Namespace private var photoTransitionNamespace

    /// 响应式过滤掉已放入待删除废纸篓的素材
    private var displayedPhotos: [PhotoAsset] {
        localPhotos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    /// 按天聚合的分组列表
    private var sections: [PhotoDateSection] {
        Self.groupPhotosByDay(displayedPhotos)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isLoading && localPhotos.isEmpty {
                    loadingGrid
                        .padding(.top, 8)
                } else if displayedPhotos.isEmpty {
                    emptyStateView
                } else {
                    photoStreamContent
                }
            }
            .background(Color.pageBackground)
            .allowsHitTesting(canSelectPhoto && !isFullscreenMode)
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .onChange(of: selectionManager.isSelectMode) { _, newValue in
            photoManager.isSelectMode = newValue
        }
        .background(Color.pageBackground)
        .navigationTitle(navigationBarTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(selectionManager.isSelectMode)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if selectionManager.isSelectMode {
                    Button(String(localized: "Cancel")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectionManager.clearSelection()
                        }
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.primary)
                }
            }

            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(navigationBarTitle)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if !selectionManager.isSelectMode && !displayedPhotos.isEmpty {
                        Text(String(localized: "\(displayedPhotos.count) Photos"))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if selectionManager.isSelectMode {
                    Button {
                        SoundManager.playAction()
                        let selected = displayedPhotos.filter { selectionManager.isSelected($0.id) }
                        for photo in selected {
                            photoManager.addToTrash(photo)
                        }
                        selectionManager.clearSelection()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text(String(localized: "Delete"))
                                .font(.system(.body, design: .rounded))
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .tint(.red)
                    .disabled(selectionManager.isEmpty)
                } else {
                    HStack(spacing: 4) {
                        // 密度切换菜单（2列 / 3列 / 4列）
                        columnSwitcherMenu

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectionManager.enterSelectMode()
                            }
                        } label: {
                            Text(String(localized: "Select"))
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
        .dynamicSecondaryNavigationBar()
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $isFullscreenMode) {
            if let photoID = currentPhotoID {
                FullscreenPhotoBrowser(
                    photos: displayedPhotos,
                    initialPhotoID: photoID,
                    onDelete: { photo in
                        photoManager.addToTrash(photo)
                    },
                    onFavoriteToggled: { photo, isFavorite in
                        if let index = localPhotos.firstIndex(where: { $0.id == photo.id }) {
                            localPhotos[index].isFavorite = isFavorite
                        }
                    },
                    onActivePhotoChange: { photo, _ in
                        currentPhotoID = photo.id
                    },
                    onDismiss: {
                        isFullscreenMode = false
                        canSelectPhoto = true
                    }
                )
                .environmentObject(photoManager)
                .navigationTransition(.zoom(sourceID: currentPhotoID ?? photoID, in: photoTransitionNamespace))
            }
        }
        .task {
            await loadInitialPhotos()
        }
        .alert(String(localized: "Cannot Delete"), isPresented: $showFavoriteDeleteAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "This photo is in your favorites. Remove from favorites first before deleting."))
        }
    }

    // MARK: - Navigation Bar Title
    private var navigationBarTitle: String {
        if selectionManager.isSelectMode {
            return String(localized: "\(selectionManager.count) Selected")
        }
        return streamTitle
    }

    // MARK: - Photo Stream Content
    private var photoStreamContent: some View {
        LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
            ForEach(sections) { section in
                Section {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: streamColumnCount)
                    LazyVGrid(columns: columns, spacing: gridSpacing) {
                        ForEach(section.photos) { photo in
                            cellForPhoto(photo)
                        }
                    }
                    .padding(.horizontal, gridPadding)
                } header: {
                    stickySectionHeader(title: section.title, count: section.photos.count)
                }
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - Sticky Date Header
    private func stickySectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Spacer()

            Text(String(localized: "\(count) Photos"))
                .font(.system(size: 12.5, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(.ultraThinMaterial)
    }

    // MARK: - Photo Cell
    @ViewBuilder
    private func cellForPhoto(_ photo: PhotoAsset) -> some View {
        let isSelected = selectionManager.isSelected(photo.id)
        let isSelectMode = selectionManager.isSelectMode
        let isFav = photoManager.isFavorite(photo)
        let cornerRadius: CGFloat = streamColumnCount == 2 ? 10 : (streamColumnCount == 3 ? 4 : 0)

        let cell = PhotoCell(
            photo: photo,
            isSelected: isSelected,
            isSelectMode: isSelectMode,
            usesSquareRatio: true,
            cornerRadius: cornerRadius
        )
        .id(photo.id)
        .matchedTransitionSource(id: photo.id, in: photoTransitionNamespace) { source in
            source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectionManager.isSelectMode {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectionManager.toggle(photo.id)
                }
            } else {
                guard canSelectPhoto && !isFullscreenMode else { return }
                canSelectPhoto = false
                currentPhotoID = photo.id
                isFullscreenMode = true
            }
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectionManager.toggle(photo.id)
            }
        }

        cell.swipeToTrash(
            photo: photo,
            isEnabled: !isSelectMode && !isFullscreenMode,
            isFavorite: isFav,
            onTrash: { targetPhoto in
                photoManager.addToTrash(targetPhoto)
            },
            onBlocked: {
                showFavoriteDeleteAlert = true
            }
        )
    }

    // MARK: - Column Switcher Menu
    private var columnSwitcherMenu: some View {
        Menu {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    streamColumnCount = 2
                }
            } label: {
                Label(String(localized: "2 Columns"), systemImage: "square.grid.2x2")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    streamColumnCount = 3
                }
            } label: {
                Label(String(localized: "3 Columns"), systemImage: "square.grid.3x3")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    streamColumnCount = 4
                }
            } label: {
                Label(String(localized: "4 Columns"), systemImage: "square.grid.4x3.fill")
            }
        } label: {
            Image(systemName: columnIcon(for: streamColumnCount))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private func columnIcon(for count: Int) -> String {
        switch count {
        case 2: return "square.grid.2x2"
        case 4: return "square.grid.4x3.fill"
        default: return "square.grid.3x3"
        }
    }

    private var gridSpacing: CGFloat {
        switch streamColumnCount {
        case 2: return 8
        case 4: return 2
        default: return 3
        }
    }

    private var gridPadding: CGFloat {
        switch streamColumnCount {
        case 2: return 12
        case 4: return 1
        default: return 2
        }
    }

    // MARK: - Data Loading
    private func loadInitialPhotos() async {
        if !initialPhotos.isEmpty {
            self.localPhotos = initialPhotos
            return
        }

        if let fetch = fetchPhotos {
            isLoading = true
            let photos = await fetch()
            self.localPhotos = photos
            isLoading = false
        }
    }

    // MARK: - Grouping Helper
    private static func groupPhotosByDay(_ photos: [PhotoAsset]) -> [PhotoDateSection] {
        let calendar = Calendar.current
        var sections: [PhotoDateSection] = []
        var currentKey = ""
        var currentTitle = ""
        var currentPhotos: [PhotoAsset] = []

        for photo in photos {
            let date = photo.asset.creationDate ?? Date()
            let key = date.formatted(.dateTime.year().month().day())
            if key == currentKey {
                currentPhotos.append(photo)
            } else {
                if !currentPhotos.isEmpty {
                    sections.append(PhotoDateSection(id: currentKey, title: currentTitle, photos: currentPhotos))
                }
                currentKey = key
                currentTitle = formatDateHeader(date, calendar: calendar)
                currentPhotos = [photo]
            }
        }
        if !currentPhotos.isEmpty {
            sections.append(PhotoDateSection(id: currentKey, title: currentTitle, photos: currentPhotos))
        }
        return sections
    }

    private static func formatDateHeader(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            let monthDay = date.formatted(.dateTime.month().day())
            return "\(monthDay) · \(String(localized: "Today"))"
        } else if calendar.isDateInYesterday(date) {
            let monthDay = date.formatted(.dateTime.month().day())
            return "\(monthDay) · \(String(localized: "Yesterday"))"
        } else {
            return date.formatted(.dateTime.year().month().day().weekday(.short))
        }
    }

    // MARK: - Loading & Empty States
    private var loadingGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: streamColumnCount)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<18, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.systemGray5))
                    .aspectRatio(1.0, contentMode: .fit)
                    .shimmering(cornerRadius: 4)
            }
        }
        .padding(.horizontal, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48, design: .rounded))
                .foregroundColor(.secondary)
            Text(String(localized: "No Photos Found"))
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}
