import SwiftUI
import Photos

struct OrganizeResultsView: View {
    var organizeManager: PhotoOrganizeManager
    let category: OrganizeCategory
    @ObservedObject var photoManager: PhotoManager
    @EnvironmentObject var membershipManager: MembershipManager
    @State private var selectionManager = SelectionManager()
    @State private var showDeleteConfirm = false
    @State private var selectedSizeText = ByteFormatter.format(0)
    @State private var categorySizeText = ""

    // 删除反馈轻提示（显示约 2 秒后自动淡出）
    @State private var deleteToastText: String?
    @State private var deleteToastDismissTask: Task<Void, Never>?
    // 非会员首次移入待处理时提示一次「永久删除需专业版」（之后不再打扰）
    @AppStorage("hasShownPendingMembershipHint") private var hasShownPendingMembershipHint = false

    // 日期分节：相似/重复按拍摄日聚合分节；其他分类按拍摄年月归类
    @State private var dateSections: [DateSection] = []
    @State private var sectionSizes: [String: Int64] = [:]
    @State private var sectionSizesTask: Task<Void, Never>? = nil
    @State private var cachedAllPhotos: [PhotoAsset] = []
    @State private var photoIndexMap: [String: Int] = [:]
    @State private var sizeCalculationTask: Task<Void, Never>? = nil

    // 详情页（大图浏览：复用共享组件 FullscreenPhotoBrowser）
    @State private var isFullscreenMode = false
    @State private var currentPhotoID: String? = nil

    init(organizeManager: PhotoOrganizeManager, category: OrganizeCategory, photoManager: PhotoManager) {
        self.organizeManager = organizeManager
        self.category = category
        self.photoManager = photoManager
        self._dateSections = State(initialValue: [])
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
        if !cachedAllPhotos.isEmpty {
            return cachedAllPhotos
        }
        if isGroupedMode {
            return dateSections.flatMap { $0.photos }
        } else {
            let photos = organizeManager.paginatedPhotos(for: category)
            return photos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
        }
    }

    private var bestPhotoIDs: Set<String> {
        Set(displayedGroups.compactMap { $0.bestPhotoId })
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
        .overlay(alignment: .top) { deleteToast }
        .background(Color(UIColor.systemGroupedBackground))
        .toolbar {
            if isGroupedMode {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        aiAutoSelect()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                            Text(String(localized: "AI Select"))
                                .font(.system(size: 15))
                        }
                    }
                    .disabled(allPhotos.isEmpty)
                }
            }

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
        .navigationTitle(category.localizedText)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .bottomBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $isFullscreenMode) {
            fullscreenBrowserDestination
        }
        .confirmationDialog(
            String(localized: "Add \(selectionManager.count) photos to Pending Photos?"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Add to Pending Photos"), role: .destructive) {
                deleteSelected()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "\(selectionManager.count) photos will be moved to the Trash and can be restored there. Total \(selectedSizeText)"))
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
        .onDisappear {
            sectionSizesTask?.cancel()
        }
        .onChange(of: displayedPhotos.count) { _, _ in
            rebuildDateSections()
        }
        .onChange(of: displayedGroups.count) { _, _ in
            rebuildDateSections()
        }
        .onChange(of: photoManager.pendingDeletionIDs) { _, _ in
            rebuildDateSections()
            if cachedAllPhotos.isEmpty && isFullscreenMode {
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
                if organizeManager.isCategoryAnalyzing(category) || organizeManager.isLoadingPhotos(for: category) || !organizeManager.isCategoryLoaded(category) {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text(organizeManager.isAnalyzing && !organizeManager.currentStep.isEmpty
                             ? organizeManager.currentStep
                             : String(localized: "Scanning for similar photos..."))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
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
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32, design: .rounded))
                .foregroundColor(Color(.tertiaryLabel))
            Text(category == .similar
                 ? String(localized: "No similar photos yet")
                 : String(localized: "No duplicate photos yet"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)

            if !organizeManager.isAnalyzing {
                Button {
                    organizeManager.startFullAnalysis()
                } label: {
                    Text(String(localized: "Scan Now"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Flat Body (screenshots, large files, low quality)

    private var flatBody: some View {
        ScrollView {
            subtitleView
            if dateSections.isEmpty && allPhotos.isEmpty {
                if organizeManager.isCategoryAnalyzing(category) || organizeManager.isLoadingPhotos(for: category) || !organizeManager.isCategoryLoaded(category) {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text(organizeManager.isAnalyzing && !organizeManager.currentStep.isEmpty
                             ? organizeManager.currentStep
                             : String(localized: "Loading..."))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let allSelected = isSectionAllSelected(section)
        let sectionIds = section.photos.map(\.id)
        withAnimation(.easeInOut(duration: 0.15)) {
            if allSelected {
                selectionManager.deselectAll(sectionIds)
            } else {
                selectionManager.selectAll(sectionIds)
            }
        }
    }

    /// 分类单元格（1:1）：点图片进详情页，点右上勾选区切换选中，超大图片右下角显示文件大小，滑动动态预热
    private func organizePhotoCell(_ photo: PhotoAsset) -> some View {
        PhotoCell(photo: photo, usesSquareRatio: true)
            .overlay(alignment: .bottomTrailing) {
                if category == .largeFiles {
                    FileSizeBadge(asset: photo.asset)
                }
            }
            .overlay(alignment: .topLeading) {
                if isGroupedMode && bestPhotoIDs.contains(photo.id) {
                    HStack(spacing: 2) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                        Text(String(localized: "Best"))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue)
                    .clipShape(Capsule())
                    .padding(6)
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
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectionManager.toggle(photo.id)
                    }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openFullscreen(photo)
            }
            .onAppear {
                if let globalIndex = photoIndexMap[photo.id] {
                    photoManager.preheatAssets(around: globalIndex, in: cachedAllPhotos, columnCount: 3)
                }
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

    /// 相似/重复：按拍摄日期归类聚合分节（日期倒序，不带组标号）；
    /// 平铺分类：全部照片按拍摄年月归类分节（日期倒序）
    private func rebuildDateSections() {
        var newSections = Self.buildDateSections(
            category: category,
            groups: displayedGroups,
            photos: displayedPhotos,
            pendingDeletionIDs: photoManager.pendingDeletionIDs
        )
        for i in 0..<newSections.count {
            let key = "\(newSections[i].id)_\(newSections[i].photos.count)"
            if let size = sectionSizes[key] ?? sectionSizes[newSections[i].id] {
                newSections[i].totalSize = size
            }
        }
        dateSections = newSections

        // 同步缓存扁平列表与全局索引表，驱动 O(1) 预热与极速全选
        let flat: [PhotoAsset]
        if isGroupedMode {
            flat = newSections.flatMap { $0.photos }
        } else {
            flat = displayedPhotos
        }
        cachedAllPhotos = flat

        var indexMap: [String: Int] = [:]
        indexMap.reserveCapacity(flat.count)
        for (idx, p) in flat.enumerated() {
            indexMap[p.id] = idx
        }
        photoIndexMap = indexMap

        computeSectionSizes()
    }

    fileprivate static func buildDateSections(
        category: OrganizeCategory,
        groups: [OrganizeGroupDisplay],
        photos: [PhotoAsset],
        pendingDeletionIDs: Set<String>
    ) -> [DateSection] {
        if category == .similar || category == .duplicates {
            // 每个分组保持完全独立，绝不把不同分组的照片合并在同一个九宫格内
            // 统计每个单日内出现的分组数量，若同日仅有 1 组显示单日期，若有多组则自然显示日期与时间
            var dayCountMap: [String: Int] = [:]

            var validGroups: [(group: OrganizeGroupDisplay, photos: [PhotoAsset], sampleDate: Date, dayKey: String)] = []

            for group in groups {
                let validPhotos = group.loadedPhotos.filter { !pendingDeletionIDs.contains($0.id) }
                // 相似/重复照片必须至少 2 张才能构成一组，绝不展示单张孤立照片
                guard validPhotos.count >= 2 else { continue }

                let sampleDate = validPhotos.compactMap { $0.asset.creationDate }.max()
                    ?? group.sampleDate
                    ?? .distantPast
                let dayKey = sampleDate == .distantPast ? "unknown" : sampleDate.formatted(date: .long, time: .omitted)
                dayCountMap[dayKey, default: 0] += 1

                validGroups.append((group: group, photos: validPhotos, sampleDate: sampleDate, dayKey: dayKey))
            }

            // 按拍摄时间倒序排列各分组（最新在前）
            let sortedGroups = validGroups.sorted { $0.sampleDate > $1.sampleDate }

            // 预统计同日多组的时间标题重名情况（如果在同一分钟内，则精确到秒）
            var titleCountMap: [String: Int] = [:]
            for item in sortedGroups {
                let isMultiOnSameDay = (dayCountMap[item.dayKey] ?? 0) > 1
                let title = primaryDateString(for: item.photos, showTimeIfSameDay: isMultiOnSameDay, includeSeconds: false)
                titleCountMap[title, default: 0] += 1
            }

            var sections: [DateSection] = []
            for item in sortedGroups {
                let isMultiOnSameDay = (dayCountMap[item.dayKey] ?? 0) > 1
                let baseTitle = primaryDateString(for: item.photos, showTimeIfSameDay: isMultiOnSameDay, includeSeconds: false)
                let hasCollision = (titleCountMap[baseTitle] ?? 0) > 1
                let finalTitle = hasCollision
                    ? primaryDateString(for: item.photos, showTimeIfSameDay: isMultiOnSameDay, includeSeconds: true)
                    : baseTitle

                sections.append(DateSection(
                    id: "group-\(category.rawValue)-\(item.group.id)",
                    groupID: item.group.id,
                    title: finalTitle,
                    photos: item.photos,
                    totalSize: item.group.totalSize
                ))
            }
            return sections
        } else {
            let flatPhotos = photos.filter { !pendingDeletionIDs.contains($0.id) }
            return createMonthSections(
                in: flatPhotos,
                idPrefix: "flat-\(category.rawValue)"
            )
        }
    }

    /// 提取一组照片的主日期文案：同日单组显示日期，同日多组自然显示日期+时间，跨天显示区间
    private static func primaryDateString(
        for photos: [PhotoAsset],
        showTimeIfSameDay: Bool = false,
        includeSeconds: Bool = false
    ) -> String {
        let dates = photos.compactMap { $0.asset.creationDate }.sorted()
        guard let first = dates.first else {
            return String(localized: "Unknown Date")
        }
        guard let last = dates.last else {
            let timeStyle: Date.FormatStyle.TimeStyle = includeSeconds ? .standard : .shortened
            return first.formatted(date: .long, time: showTimeIfSameDay ? timeStyle : .omitted)
        }
        let cal = Calendar.current
        if cal.isDate(first, inSameDayAs: last) {
            if showTimeIfSameDay {
                let timeStyle: Date.FormatStyle.TimeStyle = includeSeconds ? .standard : .shortened
                return first.formatted(date: .long, time: timeStyle)
            } else {
                return first.formatted(date: .long, time: .omitted)
            }
        } else {
            let fStr = first.formatted(date: .long, time: .omitted)
            let lStr = last.formatted(date: .long, time: .omitted)
            return "\(fStr) ~ \(lStr)"
        }
    }

    /// 平铺分类：按拍摄年月（降序）归类分节；无拍摄日期的按修改年月归类
    private static func createMonthSections(in photos: [PhotoAsset], idPrefix: String) -> [DateSection] {
        var monthBuckets: [Date: [PhotoAsset]] = [:]
        let calendar = Calendar.current

        for photo in photos {
            let targetDate = photo.asset.creationDate ?? photo.asset.modificationDate ?? .distantPast
            let components = calendar.dateComponents([.year, .month], from: targetDate)
            let monthStart = calendar.date(from: components) ?? targetDate
            monthBuckets[monthStart, default: []].append(photo)
        }

        var sections: [DateSection] = []
        for month in monthBuckets.keys.sorted(by: >) {
            let monthPhotos = monthBuckets[month]!
            sections.append(DateSection(
                id: "\(idPrefix)-month-\(month.timeIntervalSince1970)",
                groupID: idPrefix,
                title: month.formatted(Date.FormatStyle().year().month()),
                photos: monthPhotos
            ))
        }
        return sections
    }

    /// 补齐各分节合计大小（后台异步计算，单次主线程批量赋值更新；
    /// 持有任务句柄并在视图消失时取消，避免 pop 后继续占用 IO 并回写已销毁状态）
    private func computeSectionSizes() {
        let sections = dateSections
        sectionSizesTask?.cancel()
        sectionSizesTask = Task(priority: .utility) {
            var newSizes: [String: Int64] = [:]
            for section in sections {
                if Task.isCancelled { return }
                let key = "\(section.id)_\(section.photos.count)"
                guard sectionSizes[key] == nil else { continue }
                var total: Int64 = 0
                for photo in section.photos {
                    if Task.isCancelled { return }
                    total += await PHAssetSizeHelper.getAssetSize(photo.asset)
                }
                newSizes[key] = total
            }

            guard !newSizes.isEmpty, !Task.isCancelled else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                for (key, size) in newSizes {
                    sectionSizes[key] = size
                }
                for i in 0..<dateSections.count {
                    let key = "\(dateSections[i].id)_\(dateSections[i].photos.count)"
                    if let s = sectionSizes[key] {
                        dateSections[i].totalSize = s
                    }
                }
            }
        }
    }



    private func toggleSelectAll() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if selectionManager.count == allPhotos.count {
            selectionManager.clearSelection()
        } else {
            let allIds = allPhotos.map(\.id)
            selectionManager.selectAll(allIds)
        }
    }

    // MARK: - Bottom Floating Delete Button（系统原生质感蓝色大按钮）

    private var deleteButtonTitle: String {
        if !selectedSizeText.isEmpty && selectedSizeText != ByteFormatter.format(0) {
            return String(localized: "Add \(selectionManager.count) Photos to Pending Photos (\(selectedSizeText))")
        } else {
            return String(localized: "Add \(selectionManager.count) Photos to Pending Photos")
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

    /// AI 帮选：每组自动选中除最优照片外的全部成员（保留最优，其余待删），单次批量更新并触觉反馈
    private func aiAutoSelect() {
        guard isGroupedMode else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var idsToSelect: [String] = []
        for group in displayedGroups {
            let photos = filtered(group.loadedPhotos)
            guard photos.count >= 2 else { continue }
            for photo in photos where photo.id != group.bestPhotoId {
                idsToSelect.append(photo.id)
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectionManager.selectAll(idsToSelect)
        }
    }

    // MARK: - Helpers

    /// 执行删除：所选照片全部移入待处理照片，并清空选中状态
    /// （震动反馈由 addToTrash 统一触发；toast 在全屏浏览时不可见，返回后仍短暂可见）
    private func deleteSelected() {
        let selected = allPhotos.filter { selectionManager.isSelected($0.id) }
        guard !selected.isEmpty else { return }
        photoManager.addToTrash(selected)
        selectionManager.clearSelection()
        showDeleteToast(count: selected.count)
    }

    // MARK: - Delete Toast（删除后「已移入待处理照片」轻提示）

    private func showDeleteToast(count: Int) {
        let base = String(localized: "Moved \(count) photos to Pending Photos")
        var duration: UInt64 = 2_000_000_000

        // 非会员首次移入待处理：追加「永久删除需专业版」提示，
        // 在用户开始投入整理劳动时即设定免费/付费分界预期，只提示一次
        if !membershipManager.isPremiumMember && !hasShownPendingMembershipHint {
            hasShownPendingMembershipHint = true
            deleteToastText = base + "\n" + String(localized: "First Pending Hint")
            duration = 3_500_000_000
        } else {
            deleteToastText = base
        }

        deleteToastDismissTask?.cancel()
        deleteToastDismissTask = Task {
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                deleteToastText = nil
            }
        }
    }

    private var deleteToast: some View {
        VStack {
            if let text = deleteToastText {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(text)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: deleteToastText)
        .allowsHitTesting(false)
    }

    /// 选中合计大小：带 0.1s 防抖、内存缓存优先、未缓存 16 并发计算
    private func updateSelectedSize() {
        sizeCalculationTask?.cancel()

        let selected = allPhotos.filter { selectionManager.isSelected($0.id) }
        guard !selected.isEmpty else {
            selectedSizeText = ByteFormatter.format(0)
            return
        }

        let selectedAssets = selected.map(\.asset)
        sizeCalculationTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }

            let total = await Task.detached(priority: .userInitiated) {
                var uncachedAssets: [PHAsset] = []
                var sum: Int64 = 0

                for asset in selectedAssets {
                    if let cached = PHAssetSizeHelper.getCachedSize(for: asset) {
                        sum += cached
                    } else {
                        uncachedAssets.append(asset)
                    }
                }

                guard !uncachedAssets.isEmpty else { return sum }

                let uncachedSum = await withTaskGroup(of: Int64.self, returning: Int64.self) { group in
                    let maxConcurrent = 16
                    var running = 0
                    var groupTotal: Int64 = 0

                    for asset in uncachedAssets {
                        if running >= maxConcurrent {
                            if let s = await group.next() {
                                groupTotal += s
                                running -= 1
                            }
                        }
                        group.addTask {
                            PHAssetSizeHelper.getFileSize(asset)
                        }
                        running += 1
                    }

                    for await s in group {
                        groupTotal += s
                    }
                    return groupTotal
                }

                return sum + uncachedSum
            }.value

            guard !Task.isCancelled else { return }
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
                let maxConcurrent = 16
                var running = 0
                var total: Int64 = 0

                for asset in assets {
                    if running >= maxConcurrent {
                        if let size = await group.next() {
                            total += size
                            running -= 1
                        }
                    }
                    group.addTask {
                        await PHAssetSizeHelper.getAssetSize(asset)
                    }
                    running += 1
                }
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
                    showDeleteToast(count: 1)
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
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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

