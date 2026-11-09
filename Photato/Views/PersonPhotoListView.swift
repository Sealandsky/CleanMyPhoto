import SwiftUI
import Photos

// MARK: - Person Photo List View
/// 二级人物专属照片流详情页：
/// 1. 顶部 Hero 头像 (72×72pt) 与可点击内联重命名标题；
/// 2. 统计摘要与时间跨度；
/// 3. 3 列自适应照片网格（AdaptivePhotoGrid），支持缩放进全屏大图、单手滑动待删与批量多选；
/// 4. 右上角常驻标准 38×38pt PendingPhotosEntryButton 待处理废纸篓入口。
struct PersonPhotoListView: View {
    let personID: String
    @ObservedObject var peopleManager: PeopleRecognitionManager
    @ObservedObject var photoManager: PhotoManager

    @Environment(\.dismiss) private var dismiss
    @Environment(GridSettings.self) private var gridSettings

    @State private var selectionManager = SelectionManager()
    @State private var isFullscreenMode = false
    @State private var canSelectPhoto = true
    @State private var currentPhotoID: String? = nil
    @State private var targetScrollPhotoID: String? = nil
    @State private var showRenameAlert = false
    @State private var editingName = ""
    @State private var showFavoriteDeleteAlert = false
    @State private var fetchedPhotos: [PhotoAsset] = []
    @Namespace private var photoTransitionNamespace

    private var person: PersonEntity? {
        peopleManager.people.first(where: { $0.id == personID })
    }

    /// 过滤掉已放入待删除废纸篓的素材
    private var displayedPhotos: [PhotoAsset] {
        fetchedPhotos.filter { !photoManager.pendingDeletionIDs.contains($0.id) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // 1. 顶部 Hero 头像与姓名区域
                    if !selectionManager.isSelectMode, let person = person {
                        headerHeroView(person: person)
                    }

                    // 2. 照片内容区
                    if displayedPhotos.isEmpty {
                        emptyStateView
                    } else {
                        photoGridView
                            .padding(.top, 8)
                    }
                }
            }
            .background(Color.pageBackground)
            .allowsHitTesting(canSelectPhoto && !isFullscreenMode)
            .onAppear {
                loadPhotos()
            }
            .onChange(of: person?.photoIDs) { _, _ in
                loadPhotos()
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .onChange(of: selectionManager.isSelectMode) { _, newValue in
            photoManager.isSelectMode = newValue
        }
        .background(Color.pageBackground)
        .navigationTitle(selectionManager.isSelectMode ? String(localized: "\(selectionManager.count) Selected") : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(selectionManager.isSelectMode)
        .toolbar {
            if selectionManager.isSelectMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectionManager.clearSelection()
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        deleteSelectedPhotos()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(selectionManager.count == 0)
                }
            } else {
                ToolbarItem(placement: .principal) {
                    Text(person?.displayName() ?? String(localized: "People"))
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    PendingPhotosEntryButton()
                }
            }
        }
        .alert(
            (person?.name.isEmpty ?? true) ? String(localized: "Name This Person") : String(localized: "Rename Person"),
            isPresented: $showRenameAlert
        ) {
            TextField(String(localized: "Enter name"), text: $editingName)
                .textInputAutocapitalization(.words)

            Button(String(localized: "Save")) {
                if let p = person {
                    peopleManager.rename(p, to: editingName)
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                editingName = ""
            }
        }
        .alert(String(localized: "Favorite Photo"), isPresented: $showFavoriteDeleteAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "Unfavorite before moving to Pending Photos."))
        }
        .navigationDestination(isPresented: $isFullscreenMode) {
            if let photoID = currentPhotoID {
                FullscreenPhotoBrowser(
                    photos: displayedPhotos,
                    initialPhotoID: photoID,
                    onDelete: { photo in
                        photoManager.addToTrash(photo)
                    },
                    onFavoriteToggled: { photo, isFavorite in
                        photoManager.toggleFavorite(photo)
                    },
                    onActivePhotoChange: { photo, _ in
                        currentPhotoID = photo.id
                        targetScrollPhotoID = photo.id
                    },
                    onDismiss: {
                        isFullscreenMode = false
                    }
                )
                .environmentObject(photoManager)
                .navigationTransition(.zoom(sourceID: currentPhotoID ?? photoID, in: photoTransitionNamespace))
            }
        }
    }

    // MARK: - Header Hero View
    private func headerHeroView(person: PersonEntity) -> some View {
        VStack(spacing: 12) {
            // 72×72pt 大号人脸头像，带呼吸微光晕
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 84, height: 84)

                PersonAvatarView(
                    assetID: person.avatarAssetID,
                    faceCropRect: person.faceCropRect,
                    size: 72,
                    showBorder: true
                )
            }
            .padding(.top, 12)

            // 姓名（可点击唤起重命名）
            Button {
                editingName = person.name
                showRenameAlert = true
            } label: {
                HStack(spacing: 6) {
                    Text(person.displayName())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
            }
            .buttonStyle(.plain)

            // 统计摘要
            Text(String(format: String(localized: "%lld Photos"), Int64(displayedPhotos.count)))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)

            // 设备端隐私保证小标
            HStack(spacing: 4) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 10))
                Text(String(localized: "People recognition runs entirely on your device. No photos or face data ever leave your phone."))
                    .font(.system(size: 11, design: .rounded))
            }
            .foregroundColor(.secondary.opacity(0.75))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 2)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Photo Grid View
    private var photoGridView: some View {
        AdaptivePhotoGrid(photos: displayedPhotos) { photo in
            let isSelected = selectionManager.isSelected(photo.id)
            let isSelectMode = selectionManager.isSelectMode
            let isFav = photoManager.isFavorite(photo)

            PhotoCell(
                photo: photo,
                isSelected: isSelected,
                isSelectMode: isSelectMode
            )
            .id(photo.id)
            .matchedTransitionSource(id: photo.id, in: photoTransitionNamespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelectMode {
                    selectionManager.toggle(photo.id)
                } else {
                    currentPhotoID = photo.id
                    isFullscreenMode = true
                }
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectionManager.toggle(photo.id)
                }
            }
            .swipeToTrash(
                photo: photo,
                isEnabled: !isSelectMode,
                isFavorite: isFav,
                onTrash: { _ in
                    photoManager.addToTrash(photo)
                },
                onBlocked: {
                    showFavoriteDeleteAlert = true
                }
            )
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 52))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.top, 60)

            Text(String(localized: "No Photos for This Person"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Text(String(localized: "Photos may have been moved to Pending Photos."))
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Data Loading & Actions
    private func loadPhotos() {
        guard let p = person, !p.photoIDs.isEmpty else {
            fetchedPhotos = []
            return
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: p.photoIDs, options: nil)
        var list: [PhotoAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            list.append(PhotoAsset(asset: asset))
        }

        // 保持与 person.photoIDs 相同的前后顺序
        let idOrder = Dictionary(uniqueKeysWithValues: p.photoIDs.enumerated().map { ($0.element, $0.offset) })
        list.sort { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

        self.fetchedPhotos = list
    }

    private func deleteSelectedPhotos() {
        let toDelete = displayedPhotos.filter { selectionManager.isSelected($0.id) }
        for photo in toDelete {
            photoManager.addToTrash(photo)
        }
        selectionManager.clearSelection()
    }
}
