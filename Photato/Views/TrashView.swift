import SwiftUI
import StoreKit
import Photos

// MARK: - Trash View (待处理照片页面)
/// 1. 3 列标准 1:1 正方形紧凑网格（间距 3pt，圆角 4pt）；
/// 2. 底部操作栏锁定 50pt 恒定高度，加载圈原位槽位替换，杜绝高度跳动；
/// 3. 右上角显式「选择」多选按钮；
/// 4. 点击单张呼起全屏大图复核面板；
/// 5. 顶部释放空间与张数概览摘要条。
struct TrashView: View {
    @ObservedObject var photoManager: PhotoManager
    @EnvironmentObject var membershipManager: MembershipManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @State private var showingRestoreConfirmation = false
    @State private var showMembershipPaywall = false
    @State private var isDeleting = false
    @State private var selectionManager = SelectionManager()
    @State private var previewingPhoto: PhotoAsset? = nil

    private var trashedPhotos: [PhotoAsset] { photoManager.getTrashedAssets() }

    // 3 列标准 1:1 正方形紧凑网格
    private let trashColumns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if photoManager.trashCount == 0 {
                    emptyTrashView
                } else {
                    trashContent
                }
            }
            .navigationTitle(selectionManager.isSelectMode ? String(localized: "\(selectionManager.count) Selected") : String(localized: "Pending Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onAppear { AppAnalytics.screen("Pending Photos") }
            .toolbar {
                // 左侧：关闭 / 退出多选
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if selectionManager.isSelectMode {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectionManager.clearSelection()
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        // 一层玻璃原则（Colo msg 469）：工具栏自带玻璃胶囊，符号必须裸放；
                        // xmark.circle.fill 自带圆形底，会与胶囊叠成双层。
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }

                // 右侧：显式多选切换按钮
                ToolbarItem(placement: .primaryAction) {
                    if photoManager.trashCount > 0 {
                        Button {
                            SoundManager.playAction()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectionManager.isSelectMode {
                                    selectionManager.clearSelection()
                                } else {
                                    selectionManager.enterSelectMode()
                                }
                            }
                        } label: {
                            Text(selectionManager.isSelectMode ? String(localized: "Done") : String(localized: "Select"))
                                .font(.system(size: 16, weight: selectionManager.isSelectMode ? .semibold : .regular, design: .rounded))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .dynamicSecondaryNavigationBar()
            .safeAreaInset(edge: .bottom) {
                bottomFloatingBar
            }
            .confirmationDialog(String(localized: "Restore All Photos"), isPresented: $showingRestoreConfirmation) {
                Button(String(localized: "Cancel"), role: .cancel) { }
                Button(String(localized: "Restore All")) {
                    SoundManager.playAction()
                    withAnimation {
                        photoManager.restoreAllFromTrash()
                        dismiss()
                    }
                }
            } message: {
                Text(String(localized: "Restore \(photoManager.trashCount) photos to your library?"))
            }
            .sheet(item: $previewingPhoto) { photo in
                TrashPhotoPreviewSheet(photo: photo) {
                    withAnimation {
                        photoManager.restoreFromTrash(photo.id)
                    }
                }
            }
            .sheet(isPresented: $showMembershipPaywall) {
                MembershipView(isMandatory: true)
            }
            .animation(.easeInOut(duration: 0.2), value: selectionManager.isSelectMode)
        }
    }

    // MARK: - 底部悬浮操作栏（锁定 50pt 恒定高度，原位 Loading 槽位）
    @ViewBuilder
    private var bottomFloatingBar: some View {
        if photoManager.trashCount > 0 {
            HStack(spacing: 12) {
                if selectionManager.isSelectMode {
                    liquidGlassCapsule(tint: .green, prominent: false) {
                        let selected = Array(selectionManager.selectedIDs)
                        withAnimation {
                            photoManager.restoreFromTrash(selected)
                            selectionManager.clearSelection()
                        }
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
                    .disabled(isDeleting)

                    liquidGlassCapsule(tint: .red, prominent: true) {
                        guard membershipManager.isPremiumMember || membershipManager.hasFreeDeletionQuota else {
                            showMembershipPaywall = true
                            return
                        }
                        guard !isDeleting else { return }
                        isDeleting = true
                        Task {
                            defer { isDeleting = false }
                            if let result = await photoManager.emptyTrash() {
                                photoManager.pendingCleanupResult = result
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isDeleting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .frame(width: 16, height: 16)
                            } else if !membershipManager.isPremiumMember && !membershipManager.hasFreeDeletionQuota {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .frame(width: 16, height: 16)
                            }

                            Text(isDeleting ? String(localized: "Emptying...") : String(localized: "Empty Trash"))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                    }
                    .disabled(isDeleting)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .animation(.easeInOut(duration: 0.2), value: selectionManager.isSelectMode)
        }
    }

    /// 系统 Liquid Glass 胶囊按钮：锁定 44pt 恒定高度
    @ViewBuilder
    private func liquidGlassCapsule(tint: Color,
                                    prominent: Bool = false,
                                    action: @escaping () -> Void,
                                    @ViewBuilder label: @escaping () -> some View) -> some View {
        let button = Button {
            SoundManager.playAction()
            action()
        } label: {
            label()
                .frame(maxWidth: .infinity)
                .frame(height: 44) // 锁定胶囊高度 44pt
        }
        .controlSize(.regular)
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

            Text(String(localized: "Photos you clean up will appear here first. Nothing is permanently deleted until you empty the list."))
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if !membershipManager.isPremiumMember {
                Text(membershipManager.quotaDisplayText)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Trash Content
    private var trashContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                membershipHintBar

                // 优化点：体积与张数预估摘要条
                trashSummaryBar

                // 3 列标准 1:1 正方形相片网格
                LazyVGrid(columns: trashColumns, spacing: 3) {
                    ForEach(trashedPhotos) { photo in
                        PhotoCell(
                            photo: photo,
                            isSelected: selectionManager.isSelected(photo.id),
                            isSelectMode: selectionManager.isSelectMode,
                            usesSquareRatio: true,
                            cornerRadius: 4
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectionManager.isSelectMode {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectionManager.toggle(photo.id)
                                }
                            } else {
                                previewingPhoto = photo
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    // MARK: - 摘要概览条
    private var trashSummaryBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.accentColor)
                Text(String(localized: "\(photoManager.trashCount) Photos Pending"))
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }

            Spacer()

            Text(estimatedSizeText)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.cardBackground)
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var estimatedSizeText: String {
        let bytes = Int64(photoManager.trashCount) * 4_200_000
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        let formatted = formatter.string(fromByteCount: bytes)
        return String(localized: "Est. \(formatted)")
    }

    // MARK: - 会员提示条
    @ViewBuilder
    private var membershipHintBar: some View {
        if !membershipManager.isPremiumMember {
            if membershipManager.freeDeletionsRemaining > 0 {
                Button {
                    showMembershipPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(String(localized: "Free Deletion Quota Bar \(membershipManager.freeDeletionsRemaining)"))
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .opacity(0.7)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(0.08))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            } else {
                Button {
                    showMembershipPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(String(localized: "Free Quota Exhausted Bar"))
                            .font(.system(size: 14, design: .rounded))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Trash Photo Preview Sheet (待处理照片大图复核面板)
private struct TrashPhotoPreviewSheet: View {
    let photo: PhotoAsset
    let onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                AssetImage(
                    asset: photo.asset,
                    targetSize: CGSize(width: 1200, height: 1200),
                    contentMode: .fit,
                    highQuality: true
                )
                .ignoresSafeArea(edges: .horizontal)
            }
            .navigationTitle(photo.asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        // 一层玻璃原则：深色工具栏自带玻璃圆底，去掉自备的 ultraThinMaterial 圆片
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    SoundManager.playAction()
                    onRestore()
                    dismiss()
                } label: {
                    Label(String(localized: "Restore This Photo"), systemImage: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
    }
}

#Preview {
    TrashView(photoManager: PhotoManager())
        .environment(GridSettings())
        .environmentObject(MembershipManager())
}
