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
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
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
                // 免费用户追加额度消耗提示（消耗数封顶为剩余额度）；会员保持原文案
                if membershipManager.isPremiumMember {
                    Text(String(localized: "Permanently delete \(photoManager.trashCount) photos? This cannot be undone."))
                } else {
                    let consumed = min(photoManager.trashCount, membershipManager.freeDeletionsRemaining)
                    let remainingAfter = max(0, membershipManager.freeDeletionsRemaining - photoManager.trashCount)
                    Text(String(localized: "Free Quota Delete Message \(photoManager.trashCount) \(consumed) \(remainingAfter)"))
                }
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
                        // 门槛：会员或仍有免费额度即可清空；两者皆无才弹会员墙
                        guard membershipManager.isPremiumMember || membershipManager.hasFreeDeletionQuota else {
                            showMembershipPaywall = true
                            return
                        }
                        showingDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            // 非会员且免费额度用尽时按钮带锁标预告知：点击后才弹付费墙不显突兀
                            if !membershipManager.isPremiumMember && !membershipManager.hasFreeDeletionQuota {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            Text(String(localized: "Empty Trash"))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
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

            Text(String(localized: "Photos you clean up will appear here first. Nothing is permanently deleted until you empty the list."))
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // 空态同样展示额度信息（免费用户），保持额度感知贯穿回收站
            if !membershipManager.isPremiumMember {
                Text(membershipManager.quotaDisplayText)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Trash Content
    /// 排列方式与图片列表保持一致：跟随设置页的网格设置
    /// （原比例 → 瀑布流；1:1 / 3:4 → 固定列网格），由 AdaptivePhotoGrid + PhotoCell 统一处理
    private var trashContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                membershipHintBar
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
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    /// 回收站顶部提示条（会员感知三态）：
    /// · 会员（含试用期）：不显示——会员不受额度约束
    /// · 免费有额度：蓝色额度条「剩余 X/100 张免费删除额度」
    /// · 免费已用尽：可点击的升级引导条 → 弹会员墙
    @ViewBuilder
    private var membershipHintBar: some View {
        if !membershipManager.isPremiumMember {
            if membershipManager.freeDeletionsRemaining > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(String(localized: "Free Deletion Quota Bar \(membershipManager.freeDeletionsRemaining)"))
                        .font(.system(size: 14, design: .rounded))
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
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

#Preview {
    TrashView(photoManager: PhotoManager())
        .environment(GridSettings())
}
