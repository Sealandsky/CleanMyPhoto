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
                        ForEach(photoManager.displayedPhotos) { photo in
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
                            .onAppear {
                                if photo.id == photoManager.displayedPhotos.last?.id {
                                    Task {
                                        await photoManager.fetchMorePhotos()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)

                    if photoManager.isLoadingMore {
                        ProgressView()
                            .foregroundColor(.white)
                            .padding()
                    }
                }
            }
            .background(Color.black)
            .coordinateSpace(name: "scrollView")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                scrollOffset = offset
                onScrollOffsetChanged?(offset)
            }
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

                let photoExists = photoManager.displayedPhotos.contains(where: { $0.id == photoID })

                if photoExists {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withTransaction(Transaction(animation: nil)) {
                            proxy.scrollTo(photoID, anchor: .center)
                        }
                    }
                } else {
                    print("⚠️ Photo \(photoID) no longer exists, skipping scroll")
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
                        let selected = photoManager.displayedPhotos.filter { selectionManager.isSelected($0.id) }
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
}

#Preview {
    PhotoListView(photoManager: PhotoManager()) { _ in }
}
