import SwiftUI
import Photos

struct OrganizeResultsView: View {
    @Bindable var organizeManager: PhotoOrganizeManager
    let category: OrganizeCategory
    @ObservedObject var photoManager: PhotoManager
    @Environment(GridSettings.self) private var gridSettings
    @State private var selectionManager = SelectionManager()
    @State private var hasInitialized = false
    @State private var isFullscreenMode = false
    @State private var currentPhotoID: String? = nil
    @State private var showTrash = false
    @State private var deleteTrigger: Int = 0
    @State private var showFavoriteDeleteAlert: Bool = false

    private var isGroupedMode: Bool {
        category == .similar || category == .duplicates
    }

    @State private var categorySizeText: String = ""

    private var subtitleText: String {
        let count = organizeManager.stat(for: category)
        let countText = String(localized: "\(count) Photos")
        if categorySizeText.isEmpty {
            return countText
        }
        return "\(countText) · \(categorySizeText)"
    }

    private var subtitleView: some View {
        HStack {
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
        let photos = isGroupedMode
            ? displayedGroups.flatMap { $0.loadedPhotos }
            : organizeManager.paginatedPhotos(for: category)
        return photos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    private var currentFullscreenPhoto: PhotoAsset? {
        guard let id = currentPhotoID else { return nil }
        return allPhotos.first { $0.id == id }
    }

    private func filtered(_ photos: [PhotoAsset]) -> [PhotoAsset] {
        photos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Group {
                if isGroupedMode {
                    groupedBody
                } else {
                    flatBody
                }
            }

            if isFullscreenMode {
                fullscreenView
            }
        }
        .background(Color.black)
        .toolbar {
            toolbarContent
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(selectionManager.isSelectMode ? String(localized: "\(selectionManager.count) Selected") : category.localizedText)
        .navigationBarTitleDisplayMode(selectionManager.isSelectMode ? .inline : .large)
        .navigationBarBackButtonHidden(selectionManager.isSelectMode)
        .onChange(of: selectionManager.isSelectMode) { _, newValue in
            photoManager.isSelectMode = newValue
        }
        .animation(.easeInOut(duration: 0.2), value: selectionManager.isSelectMode)
        .task {
            categorySizeText = SizeCache.load(category.rawValue) ?? ""
            if !hasInitialized {
                hasInitialized = true
                await organizeManager.loadCategory(category)
            }
            await calculateCategorySize()
        }
    }

    // MARK: - Grouped Body (similar/duplicates)

    private var groupedBody: some View {
        ScrollView {
            subtitleView
            if organizeManager.isLoadingPhotos(for: category) {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(displayedGroups) { group in
                        groupSection(group)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func groupSection(_ group: OrganizeGroupDisplay) -> some View {
        let photos = filtered(group.loadedPhotos)
        return VStack(spacing: 0) {
            groupHeader(group, filteredCount: photos.count)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 4),
                GridItem(.flexible(), spacing: 4)
            ], spacing: 4) {
                ForEach(photos) { photo in
                    groupPhotoCell(photo: photo, group: group)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func groupHeader(_ group: OrganizeGroupDisplay, filteredCount: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(localized: "\(filteredCount) photos"))
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    if group.totalSize > 0 {
                        Text("·")
                            .foregroundColor(.white.opacity(0.4))
                        Text(ByteFormatter.format(group.totalSize))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .font(.system(.caption, design: .rounded))

                if isGroupedMode {
                    Text(category == .duplicates
                         ? String(localized: "Identical photos")
                         : String(localized: "Similar photos"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()

            if selectionManager.isSelectMode {
                Button {
                    deselectAll(in: group)
                } label: {
                    Text(String(localized: "Keep All"))
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func groupPhotoCell(photo: PhotoAsset, group: OrganizeGroupDisplay) -> some View {
        PhotoCell(
            photo: photo,
            isSelected: selectionManager.isSelected(photo.id),
            isSelectMode: true
        )
        .overlay(alignment: .bottomLeading) {
            if photo.id == group.bestPhotoId {
                bestBadge
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FileSizeBadge(asset: photo.asset)
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectionManager.toggle(photo.id)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openFullscreen(photo)
        }
    }

    private var bestBadge: some View {
        Text(String(localized: "Best"))
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.85))
            )
            .padding(4)
    }

    // MARK: - Flat Body (screenshots, large files, low quality)

    private var flatBody: some View {
        ScrollView {
            subtitleView
            photoGrid
        }
    }

    private var photoGrid: some View {
        LazyVGrid(columns: GridColumnHelper.columns(count: gridSettings.columnCount), spacing: GridColumnHelper.spacing) {
            ForEach(displayedPhotos) { photo in
                flatPhotoCell(photo: photo)
            }

            if organizeManager.hasMorePhotos(for: category) {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .task {
                        await organizeManager.loadMorePhotos(for: category)
                    }
            }
        }
        .padding(.horizontal, 4)
    }

    private func flatPhotoCell(photo: PhotoAsset) -> some View {
        PhotoCell(
            photo: photo,
            isSelected: selectionManager.isSelected(photo.id),
            isSelectMode: true
        )
        .id(photo.id)
        .overlay(alignment: .bottomTrailing) {
            FileSizeBadge(asset: photo.asset)
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectionManager.toggle(photo.id)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openFullscreen(photo)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selectionManager.isSelectMode {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: "Cancel")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectionManager.clearSelection()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let selected = (isGroupedMode
                        ? displayedGroups.flatMap { $0.loadedPhotos }
                        : displayedPhotos)
                        .filter { selectionManager.isSelected($0.id) }
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

    // MARK: - Helpers

    private func openFullscreen(_ photo: PhotoAsset) {
        currentPhotoID = photo.id
        withAnimation(.easeInOut(duration: 0.3)) {
            isFullscreenMode = true
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
        // Compute size for other categories from loaded photos
        let photos = organizeManager.paginatedPhotos(for: category)
        guard !photos.isEmpty else { return }
        let totalSize = await withTaskGroup(of: Int64.self, returning: Int64.self) { group in
            for photo in photos {
                group.addTask {
                    await PHAssetSizeHelper.getAssetSize(photo.asset)
                }
            }
            var total: Int64 = 0
            for await size in group {
                total += size
            }
            return total
        }
        SizeCache.save(category.rawValue, size: totalSize)
        let newText = ByteFormatter.format(totalSize)
        if newText != categorySizeText { categorySizeText = newText }
    }

    // MARK: - Fullscreen View

    private var fullscreenView: some View {
        ZStack {
            Group {
                let photos = allPhotos
                if !photos.isEmpty, currentPhotoID != nil {
                    DraggablePhotoView(
                        photos: photos,
                        currentPhotoID: currentPhotoID ?? "",
                        deleteTrigger: $deleteTrigger,
                        onPhotoChange: { id, _ in
                            currentPhotoID = id
                        },
                        onDelete: { photo in
                            photoManager.addToTrash(photo)
                        },
                        onBlockedDelete: {
                            showFavoriteDeleteAlert = true
                        },
                        onDismiss: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                isFullscreenMode = false
                            }
                        },
                        screenSize: ScreenSizeHelper.screenSize
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isFullscreenMode = false
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(.title3, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())

                    Spacer()

                    Button {
                        showTrash = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(.title3, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if photoManager.trashCount > 0 {
                            Text("\(photoManager.trashCount)")
                                .font(.system(.caption2, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 4, y: -2)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                HStack(spacing: 16) {
                    Spacer()

                    Button {
                        if let photo = currentFullscreenPhoto {
                            photoManager.toggleFavorite(photo)
                        }
                    } label: {
                        Image(systemName: (currentFullscreenPhoto?.isFavorite ?? false) ? "heart.fill" : "heart")
                            .font(.system(.title3, design: .rounded))
                            .foregroundColor((currentFullscreenPhoto?.isFavorite ?? false) ? .red : .primary)
                            .frame(width: 60, height: 60)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())

                    Button {
                        deleteTrigger += 1
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(.title3, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(width: 60, height: 60)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())

                    Spacer()
                }
                .padding(.bottom, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .alert(String(localized: "Cannot Delete"), isPresented: $showFavoriteDeleteAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "This photo is in your favorites. Remove from favorites first before deleting."))
        }
        .onChange(of: allPhotos) { oldPhotos, newPhotos in
            guard let id = currentPhotoID, !newPhotos.contains(where: { $0.id == id }) else { return }
            if let oldIndex = oldPhotos.firstIndex(where: { $0.id == id }) {
                let newIndex = min(oldIndex, newPhotos.count - 1)
                currentPhotoID = newPhotos.indices.contains(newIndex) ? newPhotos[newIndex].id : newPhotos.first?.id
            } else {
                currentPhotoID = newPhotos.first?.id
            }
            if currentPhotoID == nil, !newPhotos.isEmpty {
                isFullscreenMode = false
            }
        }
        .sheet(isPresented: $showTrash) {
            TrashView(photoManager: photoManager)
        }
    }

    private func deselectAll(in group: OrganizeGroupDisplay) {
        for photo in group.loadedPhotos {
            if selectionManager.isSelected(photo.id) {
                selectionManager.toggle(photo.id)
            }
        }
    }
}

// MARK: - File Size Badge

private struct FileSizeBadge: View {
    let asset: PHAsset
    @State private var size: Int64 = 0

    var body: some View {
        Group {
            if size > 0 {
                Text(ByteFormatter.format(size))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(6)
            }
        }
        .onAppear {
            size = PHAssetSizeHelper.getFileSize(asset)
        }
    }
}
