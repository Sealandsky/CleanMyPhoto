import SwiftUI
import Photos

// MARK: - Add to Album Sheet
/// 详情页「添加到相簿」半屏面板（自包含，不依赖 AlbumManager 实例——相簿 Tab
/// 才懒创建管理器，而详情页从任意 Tab 均可进入）：
/// 1. 自行拉取用户相簿（含空相簿，添加场景空相簿同样可选）；
/// 2. 一次查询「已包含当前素材」的相簿集合，命中行置灰标注「已添加」；
/// 3. 顶部「新建相簿」入口：输入名称，在同一个 performChanges 内完成
///    创建相簿并添加当前素材；
/// 4. 添加成功回调解锁宿主 toast 提示，面板自动关闭。
struct AddToAlbumSheet: View {
    let asset: PHAsset
    /// 添加成功回调（相簿标题）：宿主用于展示 toast
    let onAdded: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var albums: [AlbumModel] = []
    @State private var containingAlbumIDs: Set<String> = []
    @State private var isLoading = true
    /// 正在执行写入的相簿 id（行内小菊花）
    @State private var addingAlbumID: String?
    @State private var sheetToast: String?

    @State private var showNewAlbumAlert = false
    @State private var newAlbumName = ""
    @State private var isCreatingAlbum = false

    var body: some View {
        VStack(spacing: 0) {
            // iOS 26 抓手条下方内容区自动让位，此处 padding 即与抓手条的净间距：
            // 14pt 对齐系统原生面板的标题间距
            Text(String(localized: "Add to Album"))
                .font(.system(.headline, design: .rounded))
                .padding(.top, 14)
                .padding(.bottom, 14)

            if isLoading {
                Spacer(minLength: 40)
                ProgressView()
                    .tint(.secondary)
                Spacer(minLength: 40)
            } else {
                newAlbumRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if albums.isEmpty {
                            emptyAlbumsHint
                        } else {
                            ForEach(albums, id: \.id) { album in
                                albumRow(album)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = sheetToast {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                    Text(toast)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color(white: 0.12).opacity(0.92))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 5)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: sheetToast)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .background(Color(UIColor.systemGroupedBackground))
        .task { await loadAlbums() }
        .alert(String(localized: "New Album"), isPresented: $showNewAlbumAlert) {
            TextField(String(localized: "Album Name"), text: $newAlbumName)
            Button(String(localized: "Create")) {
                createAlbumAndAdd()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "The photo will be added to the new album."))
        }
    }

    // MARK: - Data

    /// 拉取用户相簿与「已包含当前素材」的相簿集合（按最近添加过排序，其余按名称字母序）
    private func loadAlbums() async {
        let fetched = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        var loaded: [AlbumModel] = []
        fetched.enumerateObjects { collection, _, _ in
            loaded.append(AlbumModel(collection: collection))
        }

        let recentIDs = RecentAlbumsStore.shared.recentAlbumIDs
        let recentIndexMap = Dictionary(uniqueKeysWithValues: recentIDs.enumerated().map { ($0.element, $0.offset) })

        albums = loaded.sorted { a, b in
            let indexA = recentIndexMap[a.id]
            let indexB = recentIndexMap[b.id]

            switch (indexA, indexB) {
            case let (idxA?, idxB?):
                return idxA < idxB
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }

        let containing = PHAssetCollection.fetchAssetCollectionsContaining(
            asset, with: .album, options: nil
        )
        var ids: Set<String> = []
        containing.enumerateObjects { collection, _, _ in
            ids.insert(collection.localIdentifier)
        }
        containingAlbumIDs = ids
        isLoading = false
    }

    // MARK: - Actions

    /// 添加当前素材到已有相簿：与 AlbumManager.addAssetToAlbum 相同的 PhotoKit 写入
    private func addToAlbum(_ album: AlbumModel) {
        guard addingAlbumID == nil else { return }
        addingAlbumID = album.id
        let albumID = album.id
        Task {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let collections = PHAssetCollection.fetchAssetCollections(
                        withLocalIdentifiers: [albumID], options: nil
                    )
                    guard let collection = collections.firstObject,
                          let request = PHAssetCollectionChangeRequest(for: collection) else { return }
                    request.addAssets([asset] as NSArray)
                }
                RecentAlbumsStore.shared.recordAlbumAdded(albumID: albumID)
                addingAlbumID = nil
                dismiss()
                onAdded(album.title)
            } catch {
                addingAlbumID = nil
                showSheetToast(String(localized: "Add failed"))
            }
        }
    }

    /// 新建相簿并直接添加当前素材：创建请求的占位集合在同一个 performChanges
    /// 内即可挂载素材，无需二次查询再写入
    private func createAlbumAndAdd() {
        let title = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreatingAlbum else { return }
        isCreatingAlbum = true
        Task {
            do {
                var createdAlbumID: String?
                try await PHPhotoLibrary.shared().performChanges {
                    // 创建请求本身即可挂载素材，无需针对占位集合再建 change request
                    let createRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                    createRequest.addAssets([asset] as NSArray)
                    createdAlbumID = createRequest.placeholderForCreatedAssetCollection.localIdentifier
                }
                if let id = createdAlbumID {
                    RecentAlbumsStore.shared.recordAlbumAdded(albumID: id)
                }
                isCreatingAlbum = false
                newAlbumName = ""
                dismiss()
                onAdded(title)
            } catch {
                isCreatingAlbum = false
                showSheetToast(String(localized: "Add failed"))
            }
        }
    }

    /// 面板内轻量 toast（写入失败等场景）：2.5 秒后自动消失
    private func showSheetToast(_ text: String) {
        sheetToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            sheetToast = nil
        }
    }

    // MARK: - Rows

    /// 「新建相簿」入口：主色调胶囊按钮
    private var newAlbumRow: some View {
        Button {
            showNewAlbumAlert = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color.accentColor)
                Text(String(localized: "New Album"))
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(Color.accentColor)
                Spacer()
                if isCreatingAlbum {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isCreatingAlbum)
    }

    private func albumRow(_ album: AlbumModel) -> some View {
        let isAdded = containingAlbumIDs.contains(album.id)
        let isAdding = addingAlbumID == album.id

        return Button {
            guard !isAdded else { return }
            addToAlbum(album)
        } label: {
            HStack(spacing: 12) {
                coverThumb(album)

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if album.assetCount > 0 {
                        Text(String(localized: "\(album.assetCount) Photos"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isAdding {
                    ProgressView()
                        .controlSize(.small)
                } else if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isAdded ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isAdding)
    }

    /// 相簿封面缩略图：无封面（空相簿）时以图标占位
    @ViewBuilder
    private func coverThumb(_ album: AlbumModel) -> some View {
        if let cover = album.coverAsset {
            AssetImage(
                asset: cover,
                targetSize: CGSize(width: 88, height: 88),
                contentMode: .fill
            )
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.tertiarySystemFill))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                )
        }
    }

    /// 无任何相簿时的空态：引导直接走「新建相簿」
    private var emptyAlbumsHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 28, design: .rounded))
                .foregroundColor(Color(.tertiaryLabel))
            Text(String(localized: "No albums yet. Create one to get started."))
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
