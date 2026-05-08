import SwiftUI
import Photos

struct OrganizeResultsView: View {
    @Bindable var organizeManager: PhotoOrganizeManager
    let category: OrganizeCategory
    @ObservedObject var photoManager: PhotoManager
    @Environment(GridSettings.self) private var gridSettings
    @State private var selectionManager = SelectionManager()
    @State private var hasInitialized = false

    private var isGroupedMode: Bool {
        category == .similar || category == .duplicates
    }

    private var displayedPhotos: [PhotoAsset] {
        organizeManager.paginatedPhotos(for: category)
    }

    private var displayedGroups: [OrganizeGroupDisplay] {
        organizeManager.groups(for: category)
    }

    var body: some View {
        if isGroupedMode {
            groupedBody
        } else {
            flatBody
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
            if !hasInitialized {
                hasInitialized = true
                await organizeManager.loadCategory(category)
            }
        }
        .onDisappear {
            organizeManager.clearCategoryState(category)
        }
    }

    // MARK: - Grouped Body (similar/duplicates)

    private var groupedBody: some View {
        ScrollView {
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
        VStack(spacing: 0) {
            groupHeader(group)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 4),
                GridItem(.flexible(), spacing: 4)
            ], spacing: 4) {
                ForEach(group.loadedPhotos) { photo in
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

    private func groupHeader(_ group: OrganizeGroupDisplay) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(localized: "\(group.loadedPhotos.count) photos"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    if group.totalSize > 0 {
                        Text("·")
                            .foregroundColor(.white.opacity(0.4))
                        Text(ByteFormatter.format(group.totalSize))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .font(.caption)

                if isGroupedMode {
                    Text(category == .duplicates
                         ? String(localized: "Identical photos")
                         : String(localized: "Similar photos"))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()

            if selectionManager.isSelectMode {
                Button {
                    deselectAll(in: group)
                } label: {
                    Text(String(localized: "Keep All"))
                        .font(.caption)
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
            isSelectMode: selectionManager.isSelectMode
        )
        .overlay(alignment: .bottomLeading) {
            if photo.id == group.bestPhotoId {
                bestBadge
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectionManager.isSelectMode {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectionManager.toggle(photo.id)
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectionManager.toggle(photo.id)
            }
        }
    }

    private var bestBadge: some View {
        Text(String(localized: "Best"))
            .font(.system(size: 9, weight: .semibold))
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
            isSelectMode: selectionManager.isSelectMode
        )
        .id(photo.id)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectionManager.isSelectMode {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectionManager.toggle(photo.id)
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectionManager.toggle(photo.id)
            }
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
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(organizeManager.stat(for: category)) \(String(localized: "photos"))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func deselectAll(in group: OrganizeGroupDisplay) {
        for photo in group.loadedPhotos {
            if selectionManager.isSelected(photo.id) {
                selectionManager.toggle(photo.id)
            }
        }
    }
}
