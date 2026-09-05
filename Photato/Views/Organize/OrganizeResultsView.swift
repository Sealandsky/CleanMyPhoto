import SwiftUI
import Photos

struct OrganizeResultsView: View {
    var organizeManager: PhotoOrganizeManager
    let category: OrganizeCategory
    @ObservedObject var photoManager: PhotoManager
    @State private var selectionManager = SelectionManager()
    @State private var showDeleteConfirm = false
    @State private var selectedSizeText = ByteFormatter.format(0)
    @State private var categorySizeText = ""

    // 日期分节：相似/重复簇按天细分；平铺分类按天分组、无日期按月归类
    @State private var dateSections: [DateSection] = []
    @State private var sectionSizes: [String: Int64] = [:]

    // 详情页（大图浏览：复用共享组件 FullscreenPhotoBrowser）
    @State private var isFullscreenMode = false
    @State private var currentPhotoID: String? = nil

    init(organizeManager: PhotoOrganizeManager, category: OrganizeCategory, photoManager: PhotoManager) {
        self.organizeManager = organizeManager
        self.category = category
        self.photoManager = photoManager

        let initialSections = Self.buildDateSections(
            category: category,
            groups: organizeManager.groups(for: category),
            photos: organizeManager.paginatedPhotos(for: category),
            pendingDeletionIDs: photoManager.pendingDeletionIDs
        )
        self._dateSections = State(initialValue: initialSections)
    }

    private var isGroupedMode: Bool {
        category == .similar || category == .duplicates
    }

    private var subtitleText: String {
        let count = organizeManager.stat(for: category)
        if categorySizeText.isEmpty {
            return String(localized: "\(count) Photos")
        }
        return String(localized: "Total \(count) photos, \(categorySizeText)")
    }


    private var subtitleView: some View {
        HStack(alignment: .center) {
            Text(subtitleText)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)

            Spacer()

            if isGroupedMode {
                Button {
                    aiAutoSelect()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(localized: "AI Select"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var displayedPhotos: [PhotoAsset] {
        organizeManager.paginatedPhotos(for: category)
            .filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    private var displayedGroups: [OrganizeGroupDisplay] {
        organizeManager.groups(for: category)
    }

    private var allPhotos: [PhotoAsset] {
        let photos = isGroupedMode
            ? displayedGroups.flatMap { $0.loadedPhotos }
            : organizeManager.paginatedPhotos(for: category)
        return photos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    private func filtered(_ photos: [PhotoAsset]) -> [PhotoAsset] {
        photos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    private var isDeleteButtonVisible: Bool {
        !selectionManager.isEmpty && !isFullscreenMode
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if isGroupedMode {
                    groupedBody
                } else {
                    flatBody
                }
            }

            deleteFloatingButton
                .offset(y: isDeleteButtonVisible ? 0 : 130)
                .opacity(isDeleteButtonVisible ? 1 : 0)
                .allowsHitTesting(isDeleteButtonVisible)
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isDeleteButtonVisible)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .toolbar {
            toolbarContent
        }
        .navigationTitle(category.localizedText)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .bottomBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $isFullscreenMode) {
            fullscreenBrowserDestination
        }
        .confirmationDialog(
            String(localized: "Delete \(selectionManager.count) photos?"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete \(selectionManager.count) Photos"), role: .destructive) {
                deleteSelected()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "\(selectionManager.count) photos will be permanently deleted and cannot be recovered. Total \(selectedSizeText)"))
        }
        .onAppear {
            if dateSections.isEmpty {
                rebuildDateSections()
            }
        }
        .task {
            categorySizeText = SizeCache.load(category.rawValue) ?? ""
            if !organizeManager.isCategoryLoaded(category) {
                await organizeManager.loadCategory(category)
                rebuildDateSections()
            }
            Task(priority: .utility) {
                await calculateCategorySize()
            }
        }
        .onChange(of: allPhotos) { _, newPhotos in
            // 分页加载/删除后分节跟随重建（尺寸缓存按键复用，不重复计算）
            rebuildDateSections()
            if newPhotos.isEmpty && isFullscreenMode {
                isFullscreenMode = false
            }
        }
        .onChange(of: selectionManager.count) { _, _ in
            updateSelectedSize()
        }
    }

    // MARK: - Grouped Body (similar/duplicates)

    private var groupedBody: some View {
        ScrollView {
            subtitleView
            if dateSections.isEmpty && allPhotos.isEmpty {
                if organizeManager.isLoadingPhotos(for: category) {
                    ProgressView()
                        .tint(.primary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    groupedEmptyView
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(dateSections) { section in
                        dateSectionView(section)
                    }
                    // 分组分批按需追加（首批 10 组瞬时上屏，到底自动追加）
                    if organizeManager.hasMoreGroups(for: category) {
                        ProgressView()
                            .tint(.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .task {
                                await organizeManager.loadMoreGroups(for: category)
                                rebuildDateSections()
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, isDeleteButtonVisible ? 80 : 20)
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isDeleteButtonVisible)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var groupedEmptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 26, design: .rounded))
                .foregroundColor(Color(.tertiaryLabel))
            Text(String(localized: "No similar photos yet"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Flat Body (screenshots, large files, low quality)

    private var flatBody: some View {
        ScrollView {
            subtitleView
            if dateSections.isEmpty && allPhotos.isEmpty {
                if organizeManager.isLoadingPhotos(for: category) {
                    ProgressView()
                        .tint(.primary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    flatEmptyView
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(dateSections) { section in
                        dateSectionView(section)
                    }
                    // 图库页同款：滚动到尾部继续分页加载
                    if organizeManager.hasMorePhotos(for: category) {
                        ProgressView()
                            .tint(.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .task {
                                await organizeManager.loadMorePhotos(for: category)
                                rebuildDateSections()
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, isDeleteButtonVisible ? 80 : 20)
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isDeleteButtonVisible)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var flatEmptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 26, design: .rounded))
                .foregroundColor(Color(.tertiaryLabel))
            Text(String(localized: "No photos in this category"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - 日期分节

    /// 分节头：左侧日期（粗体），右侧张数 + 合计大小（灰，异步补齐）+ 全选/反选复选框
    private func dateSectionView(_ section: DateSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(section.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text(String(localized: "\(section.photos.count) Photos"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)

                if section.totalSize > 0 {
                    Text(ByteFormatter.format(section.totalSize))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Button {
                    toggleSectionSelection(section)
                } label: {
                    if isSectionAllSelected(section) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .blue)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 20))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                ForEach(section.photos) { photo in
                    organizePhotoCell(photo)
                }
            }
        }
    }

    private func isSectionAllSelected(_ section: DateSection) -> Bool {
        guard !section.photos.isEmpty else { return false }
        return section.photos.allSatisfy { selectionManager.isSelected($0.id) }
    }

    private func toggleSectionSelection(_ section: DateSection) {
        let allSelected = isSectionAllSelected(section)
        withAnimation(.easeInOut(duration: 0.15)) {
            if allSelected {
                for photo in section.photos {
                    if selectionManager.isSelected(photo.id) {
                        selectionManager.toggle(photo.id)
                    }
                }
            } else {
                for photo in section.photos {
                    if !selectionManager.isSelected(photo.id) {
                        selectionManager.toggle(photo.id)
                    }
                }
            }
        }
    }

    /// 分类单元格（1:1）：点图片进详情页，点右上勾选区切换选中，超大图片右下角显示文件大小
    private func organizePhotoCell(_ photo: PhotoAsset) -> some View {
        PhotoCell(photo: photo, usesSquareRatio: true)
            .overlay(alignment: .bottomTrailing) {
                if category == .largeFiles {
                    FileSizeBadge(asset: photo.asset)
                }
            }
            .overlay(alignment: .topTrailing) {
                selectionMark(isSelected: selectionManager.isSelected(photo.id))
            }
            .overlay(alignment: .topTrailing) {
                // 勾选热区：点这里只切换选中，不进详情页
                Color.clear
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectionManager.toggle(photo.id)
                    }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openFullscreen(photo)
            }
    }

    /// 选中标记：右上角勾选，选中为系统样式（白勾 + 系统蓝圈）
    private func selectionMark(isSelected: Bool) -> some View {
        Group {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
            } else {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(Color.black.opacity(0.2)))
            }
        }
        .frame(width: 24, height: 24)
        .padding(8)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - 日期分节构建

    /// 相似/重复：每个簇按天细分（跨天的簇拆成多个日期节，日期降序）；
    /// 平铺分类：全部照片按天分组；无拍摄日期的按月归类（回退修改时间）
    private func rebuildDateSections() {
        var newSections = Self.buildDateSections(
            category: category,
            groups: displayedGroups,
            photos: displayedPhotos,
            pendingDeletionIDs: photoManager.pendingDeletionIDs
        )
        for i in 0..<newSections.count {
            if let size = sectionSizes[newSections[i].id] {
                newSections[i].totalSize = size
            }
        }
        dateSections = newSections
        computeSectionSizes()
    }

    fileprivate static func buildDateSections(
        category: OrganizeCategory,
        groups: [OrganizeGroupDisplay],
        photos: [PhotoAsset],
        pendingDeletionIDs: Set<String>
    ) -> [DateSection] {
        var sections: [DateSection] = []
        if category == .similar || category == .duplicates {
            for group in groups {
                let groupPhotos = group.loadedPhotos.filter { !pendingDeletionIDs.contains($0.id) }
                sections.append(contentsOf: createDateSections(
                    in: groupPhotos,
                    idPrefix: "group-\(group.id)"
                ))
            }
        } else {
            let flatPhotos = photos.filter { !pendingDeletionIDs.contains($0.id) }
            sections.append(contentsOf: createDateSections(
                in: flatPhotos,
                idPrefix: "flat-\(category.rawValue)"
            ))
        }
        // 跨组合并：前组尾与后组头可能同日，合并相邻同日期节避免重复日期头
        var merged: [DateSection] = []
        for section in sections {
            if let last = merged.last, last.title == section.title {
                merged[merged.count - 1].photos.append(contentsOf: section.photos)
            } else {
                merged.append(section)
            }
        }
        return merged
    }

    /// 将照片按拍摄日（降序）分节；无拍摄日期的按月归类（回退修改时间）
    private static func createDateSections(in photos: [PhotoAsset], idPrefix: String) -> [DateSection] {
        var dayBuckets: [Date: [PhotoAsset]] = [:]
        var monthBuckets: [Date: [PhotoAsset]] = [:]

        for photo in photos {
            if let created = photo.asset.creationDate {
                dayBuckets[Calendar.current.startOfDay(for: created), default: []].append(photo)
            } else if let modified = photo.asset.modificationDate {
                let month = Calendar.current.date(
                    from: Calendar.current.dateComponents([.year, .month], from: modified)
                ) ?? modified
                monthBuckets[month, default: []].append(photo)
            }
        }

        var sections: [DateSection] = []
        for day in dayBuckets.keys.sorted(by: >) {
            let photos = dayBuckets[day]!
            sections.append(DateSection(
                id: "\(idPrefix)-day-\(day.timeIntervalSince1970)",
                groupID: idPrefix,
                title: day.formatted(date: .long, time: .omitted),
                photos: photos
            ))
        }
        for month in monthBuckets.keys.sorted(by: >) {
            let photos = monthBuckets[month]!
            sections.append(DateSection(
                id: "\(idPrefix)-month-\(month.timeIntervalSince1970)",
                groupID: idPrefix,
                title: month.formatted(Date.FormatStyle().year().month()),
                photos: photos
            ))
        }

        // 相邻同日期节合并：不同簇可能落在同一天，避免重复日期头
        var merged: [DateSection] = []
        for section in sections {
            if let last = merged.last, last.title == section.title {
                merged[merged.count - 1].photos.append(contentsOf: section.photos)
            } else {
                merged.append(section)
            }
        }
        return merged
    }

    /// 补齐各分节合计大小（异步读缓存尺寸，不阻塞渲染）
    private func computeSectionSizes() {
        let sections = dateSections
        Task {
            for section in sections {
                let key = section.id
                guard sectionSizes[key] == nil else { continue }
                var total: Int64 = 0
                for photo in section.photos {
                    total += await PHAssetSizeHelper.getAssetSize(photo.asset)
                }
                sectionSizes[key] = total
                if let idx = dateSections.firstIndex(where: { $0.id == key }) {
                    dateSections[idx].totalSize = total
                }
            }
        }
    }

    // MARK: - Toolbar（右上角：全选 / 取消全选）

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                toggleSelectAll()
            } label: {
                Text(selectionManager.count == allPhotos.count && !allPhotos.isEmpty
                     ? String(localized: "Deselect All")
                     : String(localized: "Select All"))
                    .font(.system(size: 15))
            }
            .disabled(allPhotos.isEmpty)
        }
    }

    private func toggleSelectAll() {
        if selectionManager.count == allPhotos.count {
            selectionManager.clearSelection()
        } else {
            for photo in allPhotos {
                if !selectionManager.isSelected(photo.id) {
                    selectionManager.toggle(photo.id)
                }
            }
        }
    }

    // MARK: - Bottom Floating Delete Button（系统原生质感蓝色大按钮）

    private var deleteButtonTitle: String {
        if !selectedSizeText.isEmpty && selectedSizeText != ByteFormatter.format(0) {
            return String(localized: "Delete \(selectionManager.count) Photos (\(selectedSizeText))")
        } else {
            return String(localized: "Delete \(selectionManager.count) Photos")
        }
    }

    private var deleteFloatingButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(deleteButtonTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.blue)
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
        .padding(.bottom, 16)
    }

    /// AI 帮选：每组自动选中除最优照片外的全部成员（保留最优，其余待删）
    private func aiAutoSelect() {
        guard isGroupedMode else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            for group in displayedGroups {
                for photo in filtered(group.loadedPhotos) where photo.id != group.bestPhotoId {
                    if !selectionManager.isSelected(photo.id) {
                        selectionManager.toggle(photo.id)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// 执行删除：所选照片全部移入回收站，并清空选中状态
    private func deleteSelected() {
        let selected = allPhotos.filter { selectionManager.isSelected($0.id) }
        for photo in selected {
            photoManager.addToTrash(photo)
        }
        selectionManager.clearSelection()
    }

    /// 选中合计大小：异步累加（PHAssetSizeHelper 内部有缓存，重复查询开销小）
    private func updateSelectedSize() {
        let selected = allPhotos.filter { selectionManager.isSelected($0.id) }
        guard !selected.isEmpty else {
            selectedSizeText = ByteFormatter.format(0)
            return
        }
        Task {
            var total: Int64 = 0
            for photo in selected {
                total += await PHAssetSizeHelper.getAssetSize(photo.asset)
            }
            selectedSizeText = ByteFormatter.format(total)
        }
    }

    private func calculateCategorySize() async {
        // Use pre-computed size for largeFiles
        if let potentialSize = organizeManager.scanResults[category]?.first?.potentialSpaceSaved, potentialSize > 0 {
            SizeCache.save(category.rawValue, size: potentialSize)
            let newText = ByteFormatter.format(potentialSize)
            if newText != categorySizeText { categorySizeText = newText }
            return
        }

        // 优先使用缓存
        if let cached = SizeCache.load(category.rawValue), !cached.isEmpty {
            if categorySizeText != cached { categorySizeText = cached }
            return
        }

        let allIds = organizeManager.scanResults[category]?.flatMap { $0.localIdentifiers }
            ?? organizeManager.categoryPageStates[category]?.allIdentifiers
            ?? allPhotos.map(\.id)
        guard !allIds.isEmpty else { return }

        let totalSize = await Task.detached(priority: .utility) {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: allIds, options: nil)
            var assets: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            return await withTaskGroup(of: Int64.self, returning: Int64.self) { group in
                for asset in assets {
                    group.addTask {
                        await PHAssetSizeHelper.getAssetSize(asset)
                    }
                }
                var total: Int64 = 0
                for await size in group {
                    total += size
                }
                return total
            }
        }.value

        guard totalSize > 0 else { return }
        SizeCache.save(category.rawValue, size: totalSize)
        let newText = ByteFormatter.format(totalSize)
        if newText != categorySizeText { categorySizeText = newText }
    }

    private func openFullscreen(_ photo: PhotoAsset) {
        currentPhotoID = photo.id
        isFullscreenMode = true
    }

    // MARK: - Fullscreen Browser Destination

    @ViewBuilder
    private var fullscreenBrowserDestination: some View {
        if let photoID = currentPhotoID {
            FullscreenPhotoBrowser(
                photos: allPhotos,
                initialPhotoID: photoID,
                onDelete: { photo in
                    photoManager.addToTrash(photo)
                },
                onFavoriteToggled: { photo, isFavorite in
                    organizeManager.updateFavorite(photoID: photo.id, isFavorite: isFavorite)
                },
                onDismiss: {
                    isFullscreenMode = false
                }
            )
            .environmentObject(photoManager)
        }
    }
}

// MARK: - Date Section（日期分节）

/// 相似/重复簇按天细分、平铺分类按天分组后的展示节
private struct DateSection: Identifiable {
    let id: String
    /// 所属分组（平铺分类为 flat-key），用于按批次过滤
    let groupID: String
    let title: String
    var photos: [PhotoAsset]
    /// 分节合计大小：异步补齐（0 时不显示）
    var totalSize: Int64 = 0
}


// MARK: - File Size Badge

private struct FileSizeBadge: View {
    let asset: PHAsset
    @State private var sizeText: String = ""

    var body: some View {
        Group {
            if !sizeText.isEmpty {
                Text(sizeText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(6)
            }
        }
        .task {
            let fastSize = PHAssetSizeHelper.getFileSize(asset)
            if fastSize > 0 {
                sizeText = ByteFormatter.format(fastSize)
            } else {
                let asyncSize = await PHAssetSizeHelper.getAssetSize(asset)
                if asyncSize > 0 {
                    sizeText = ByteFormatter.format(asyncSize)
                }
            }
        }
    }
}
