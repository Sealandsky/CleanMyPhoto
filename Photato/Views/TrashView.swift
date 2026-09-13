import SwiftUI

struct TrashView: View {
    @ObservedObject var photoManager: PhotoManager
    @EnvironmentObject var membershipManager: MembershipManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false
    @State private var showingRestoreConfirmation = false
    @State private var showMembershipPaywall = false
    @Environment(GridSettings.self) private var gridSettings
    @State private var selectionManager = SelectionManager()

    private var trashedPhotos: [PhotoAsset] { photoManager.getTrashedAssets() }

    var body: some View {
        NavigationView {
            Group {
                if photoManager.trashCount == 0 {
                    emptyTrashView
                } else {
                    trashContent
                }
            }
            .navigationTitle(selectionManager.isSelectMode ? String(localized: "\(selectionManager.count) Selected") : String(localized: "Pending Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 顶部栏仅保留关闭图标：多选模式下先退出多选，否则关闭页面
                    Button {
                        if selectionManager.isSelectMode {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectionManager.clearSelection()
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomFloatingBar
            }
            .confirmationDialog(String(localized: "Restore All Photos"), isPresented: $showingRestoreConfirmation) {
                Button(String(localized: "Cancel"), role: .cancel) { }
                Button(String(localized: "Restore All")) {
                    withAnimation {
                        photoManager.restoreAllFromTrash()
                        dismiss()
                    }
                }
            } message: {
                Text(String(localized: "Restore \(photoManager.trashCount) photos to your library?"))
            }
            .alert(String(localized: "Delete All Photos"), isPresented: $showingDeleteConfirmation) {
                Button(String(localized: "Cancel"), role: .cancel) { }
                Button(String(localized: "Delete"), role: .destructive) {
                    Task {
                        await photoManager.emptyTrash()
                        dismiss()
                    }
                }
            } message: {
                Text(String(localized: "Permanently delete \(photoManager.trashCount) photos? This cannot be undone."))
            }
            .sheet(isPresented: $showMembershipPaywall) {
                MembershipView(isMandatory: true)
            }
            .animation(.easeInOut(duration: 0.2), value: selectionManager.isSelectMode)
        }
    }

    // MARK: - 底部悬浮操作栏（固定于底部，不随内容滚动）
    /// 常规模式：全部恢复 + 全部删除 等宽横向铺满；多选模式：恢复所选。
    /// 按钮为系统 Liquid Glass 原生风格（iOS 26+），旧系统回退实色胶囊
    @ViewBuilder
    private var bottomFloatingBar: some View {
        if photoManager.trashCount > 0 {
            HStack(spacing: 12) {
                if selectionManager.isSelectMode {
                    liquidGlassCapsule(tint: .green, prominent: false) {
                        for id in selectionManager.selectedIDs {
                            photoManager.restoreFromTrash(id)
                        }
                        selectionManager.clearSelection()
                    } label: {
                        Label(String(localized: "Restore \(selectionManager.count) Photos"),
                              systemImage: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .disabled(selectionManager.isEmpty)
                } else {
                    liquidGlassCapsule(tint: .green, prominent: false) {
                        showingRestoreConfirmation = true
                    } label: {
                        Text(String(localized: "Restore All"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }

                    liquidGlassCapsule(tint: .red, prominent: true) {
                        guard membershipManager.isPremiumMember || !membershipManager.isTrialExpired else {
                            showMembershipPaywall = true
                            return
                        }
                        showingDeleteConfirmation = true
                    } label: {
                        Text(String(localized: "Empty Trash"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .animation(.easeInOut(duration: 0.2), value: selectionManager.isSelectMode)
        }
    }

    /// 系统 Liquid Glass 胶囊按钮：iOS 26+ 走原生 glass 风格
    /// （prominent 为着色玻璃，用于删除等强调操作），iOS 18 回退实色胶囊。
    /// frame 加在 label 内部使胶囊本体撑满可用宽度（加在外部只会居中）
    @ViewBuilder
    private func liquidGlassCapsule(tint: Color,
                                    prominent: Bool = false,
                                    action: @escaping () -> Void,
                                    @ViewBuilder label: @escaping () -> some View) -> some View {
        let button = Button {
            action()
        } label: {
            label()
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        if #available(iOS 26.0, *) {
            if prominent {
                button.buttonStyle(.glassProminent)
                    .tint(tint)
            } else {
                button.buttonStyle(.glass)
            }
        } else {
            button.buttonStyle(.borderedProminent)
                .tint(tint)
        }
    }

    // MARK: - Empty State
    private var emptyTrashView: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash")
                .font(.system(size: 60, design: .rounded))
                .foregroundColor(.gray)

            Text(String(localized: "No Pending Photos"))
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)

            Text(String(localized: "Photos you swipe up to delete will appear here."))
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Trash Content
    /// 排列方式与图片列表保持一致：跟随设置页的网格设置
    /// （原比例 → 瀑布流；1:1 / 3:4 → 固定列网格），由 AdaptivePhotoGrid + PhotoCell 统一处理
    private var trashContent: some View {
        ScrollView {
            AdaptivePhotoGrid(photos: trashedPhotos) { photo in
                PhotoCell(
                    photo: photo,
                    isSelected: selectionManager.isSelected(photo.id),
                    isSelectMode: selectionManager.isSelectMode
                )
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
                .contextMenu {
                    Button(role: .destructive) {
                        withAnimation {
                            photoManager.restoreFromTrash(photo.id)
                        }
                    } label: {
                        Label(String(localized: "Restore"), systemImage: "arrow.uturn.backward")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    TrashView(photoManager: PhotoManager())
        .environment(GridSettings())
}
