

import SwiftUI
import Photos

struct PhotoGroupView: View {
    @ObservedObject var albumManager: SystemAlbumManager
    @ObservedObject var photoManager: PhotoManager
    let onMonthSelect: (MonthAlbum) -> Void

    var body: some View {
        Group {
            if albumManager.isLoading && albumManager.allMonthAlbums.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Text(String(localized: "Loading..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(albumManager.yearAlbums) { yearAlbum in
                            Section {
                                if let months = albumManager.allMonthAlbums[yearAlbum.year], !months.isEmpty {
                                    LazyVGrid(columns: [
                                        GridItem(.flexible()),
                                        GridItem(.flexible())
                                    ], spacing: 12) {
                                        ForEach(months) { monthAlbum in
                                            MonthCardView(monthAlbum: monthAlbum)
                                                .onTapGesture {
                                                    onMonthSelect(monthAlbum)
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                            } header: {
                                HStack {
                                    Text(verbatim: "\(yearAlbum.year)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.leading, 0)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .background(Color.black)
        .task {
            if albumManager.yearAlbums.isEmpty {
                await albumManager.fetchYearAlbums()
                await albumManager.fetchAllMonths()
            }
        }
    }
}

// MARK: - Month Card View
struct MonthCardView: View {
    let monthAlbum: MonthAlbum

    var body: some View {
        PhotoCard {
            PhotoCardCover {
                if let thumbnail = monthAlbum.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else if let asset = monthAlbum.fetchResult?.firstObject ?? monthAlbum.assets.first {
                    AssetImage(
                        asset: asset,
                        targetSize: CGSize(width: 400, height: 400),
                        contentMode: .fill
                    )
                    .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        )
                }
            }

            PhotoCardInfo(
                title: monthAlbum.monthName,
                subtitle: "\(monthAlbum.photoCount)\(String(localized: "photos"))"
            )
        }
    }
}

// MARK: - Month Photos View
struct SystemMonthPhotosView: View {
    let monthAlbum: MonthAlbum
    @ObservedObject var photoManager: PhotoManager
    let onPhotoSelect: (PhotoAsset) -> Void
    var scrollToPhotoID: String? = nil
    @Environment(GridSettings.self) private var gridSettings
    @State private var selectionManager = SelectionManager()

    private var columns: [GridItem] {
        GridColumnHelper.columns(count: gridSettings.columnCount)
    }

    private var photos: [PhotoAsset] {
        monthAlbum.photoAssets.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
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
            .background(Color.black)
            .onAppear {
                if let photoID = scrollToPhotoID {
                    proxy.scrollTo(photoID, anchor: .center)
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
        .navigationTitle(selectionManager.isSelectMode ? String(localized: "\(selectionManager.count) Selected") : monthAlbum.fullTitle)
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
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(monthAlbum.photoCount) \(String(localized: "photos"))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectionManager.isSelectMode)
    }
}

#Preview("PhotoGroupView", body: {
    PhotoGroupView(
        albumManager: SystemAlbumManager(),
        photoManager: PhotoManager(),
        onMonthSelect: { _ in }
    )
})
