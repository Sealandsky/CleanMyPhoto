import SwiftUI
import Photos

// MARK: - My Albums List View
/// 「我的相册」完整列表页：垂直排列所有用户相簿，右上角「+」新建相簿。
/// 由相册首页「My Albums」标题右侧的箭头入口进入；新建相册逻辑从首页迁移至此。
struct MyAlbumsListView: View {
    @ObservedObject var albumManager: AlbumManager
    let onAlbumSelect: (AlbumModel) -> Void

    @State private var showNewAlbumAlert = false
    @State private var newAlbumName = ""
    @State private var isCreatingAlbum = false
    @State private var errorMessage: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // 在 iPhone Duo 展开屏等宽屏设备上使用 4 列偶数网格，避开中央折痕并保持相册卡片精致尺寸
    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albumManager.albums) { album in
                    AlbumStackCell(album: album)
                        .onTapGesture {
                            onAlbumSelect(album)
                        }
                }
            }
            // 上下留白需容纳卡片投影（radius 12 + y 5 ≈ 17pt），否则被 ScrollView 裁切
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .safeAreaPadding(.horizontal)
        .background(Color.pageBackground)
        .navigationTitle(String(localized: "My Albums"))
        .navigationBarTitleDisplayMode(.inline)
        .dynamicSecondaryNavigationBar()
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newAlbumName = ""
                    showNewAlbumAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .accessibilityLabel(String(localized: "New Album"))
            }
        }
        .alert(String(localized: "New Album"), isPresented: $showNewAlbumAlert) {
            TextField(String(localized: "Album Name"), text: $newAlbumName)
                .textInputAutocapitalization(.words)

            Button(String(localized: "Create")) {
                createNewAlbum()
            }
            .disabled(newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(String(localized: "Cancel"), role: .cancel) {
                newAlbumName = ""
            }
        } message: {
            Text(String(localized: "Enter a name for this album."))
        }
        .alert(String(localized: "Failed to create album"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - 新建相簿
    private func createNewAlbum() {
        let title = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreatingAlbum else { return }
        isCreatingAlbum = true
        Task {
            do {
                _ = try await albumManager.createAlbum(title: title)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                AppAnalytics.event("album_created")
                isCreatingAlbum = false
                newAlbumName = ""
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                isCreatingAlbum = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
