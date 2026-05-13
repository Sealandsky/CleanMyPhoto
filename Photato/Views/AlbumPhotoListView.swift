import SwiftUI
import Photos

struct AlbumPhotoListView: View {
    @ObservedObject var albumManager: AlbumManager
    @ObservedObject var photoManager: PhotoManager
    let album: AlbumModel
    let onPhotoSelect: (PhotoAsset) -> Void
    var scrollToPhotoID: String? = nil
    @Environment(GridSettings.self) private var gridSettings
    @State private var selectionManager = SelectionManager()
    @State private var albumSizeText: String = ""

    private var columns: [GridItem] {
        GridColumnHelper.columns(count: gridSettings.columnCount)
    }

    private var photos: [PhotoAsset] { albumManager.displayedAlbumPhotos }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    albumInfoHeader

                    LazyVGrid(columns: columns, spacing: GridColumnHelper.spacing) {
                        ForEach(photos) { photo in
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
                                } else {
                                    onPhotoSelect(photo)
                                }
                            }
                            .onLongPressGesture(minimumDuration: 0.3) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectionManager.toggle(photo.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .background(Color.black)
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
            .onAppear {
                if let photoID = scrollToPhotoID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withTransaction(Transaction(animation: nil)) {
                            proxy.scrollTo(photoID, anchor: .center)
                        }
                    }
                }
                calculateAlbumSize()
            }
        }
        .onChange(of: selectionManager.isSelectMode) { _, newValue in
            photoManager.isSelectMode = newValue
        }
        .navigationTitle(selectionManager.isSelectMode ? String(localized: "\(selectionManager.count) Selected") : album.title)
        .navigationBarTitleDisplayMode(selectionManager.isSelectMode ? .inline : .large)
        .navigationBarBackButtonHidden(selectionManager.isSelectMode)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
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

    // MARK: - Album Info Header

    private var albumInfoHeader: some View {
        HStack(spacing: 16) {
            Text("\(photos.count) \(String(localized: "photos"))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !albumSizeText.isEmpty {
                Text(albumSizeText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Album Size Calculation

    private func calculateAlbumSize() {
        Task {
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
            albumSizeText = ByteFormatter.format(totalSize)
        }
    }
}
