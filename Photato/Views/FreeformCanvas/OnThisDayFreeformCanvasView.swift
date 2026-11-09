import SwiftUI
import Photos

// MARK: - 往年今日自由画布视图 (OnThisDay Freeform Canvas View)
struct OnThisDayFreeformCanvasView: View {
    let group: OnThisDayYearGroup
    @ObservedObject var photoManager: PhotoManager
    var resetToken: Int = 0
    let onBlocked: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    // 缩放与平移手势状态
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @GestureState private var gestureZoom: CGFloat = 1.0
    @GestureState private var gesturePan: CGSize = .zero

    // 自由画布顶部引导条持久化隐藏状态
    @AppStorage("hasDismissedCanvasGuide") private var hasDismissedCanvasGuide: Bool = false

    // 确定性布局缓存与容量统计
    @State private var cachedLayouts: [CanvasPhotoLayout] = []
    @State private var totalSizeText: String = ""

    // 抛入待处理动画与撤销状态
    @State private var tossingPhotoIDs: Set<String> = []
    @State private var lastTrashedPhoto: PhotoAsset? = nil
    @State private var showUndoToast: Bool = false
    @State private var undoDismissTimer: Task<Void, Never>? = nil

    private var effectiveScale: CGFloat {
        max(0.55, min(2.3, zoomScale * gestureZoom))
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: panOffset.width + gesturePan.width,
            height: panOffset.height + gesturePan.height
        )
    }

    /// 过滤出当前画布应可见的照片卡片布局
    private var visibleLayouts: [CanvasPhotoLayout] {
        cachedLayouts.filter { layout in
            !photoManager.pendingDeletionIDs.contains(layout.id) || tossingPhotoIDs.contains(layout.id)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. 画布底板背景
                canvasBackgroundColor
                    .ignoresSafeArea()

                if visibleLayouts.isEmpty {
                    allDoneEmptyView
                } else {
                    // 2. 2D 自由漫游照片卡片层
                    canvasContent(viewportSize: geo.size)
                }

                // 3. 悬浮顶部操作引导微胶囊（右侧支持关闭且持久化不再提醒）
                if !hasDismissedCanvasGuide && !visibleLayouts.isEmpty {
                    VStack {
                        floatingGuidePill
                            .padding(.top, 12)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // 4. 底部可撤销操作浮条 (Undo Toast)
                if showUndoToast {
                    VStack {
                        Spacer()
                        undoToastView
                            .padding(.horizontal, 20)
                            .padding(.bottom, 76)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .onAppear {
                setupLayoutIfNeeded()
                calculateSize()
            }
            .onChange(of: group.photos.count) { _, _ in
                setupLayoutIfNeeded()
                calculateSize()
            }
            .onChange(of: resetToken) { _, _ in
                // 定位按钮：视野平滑回到中心标题
                resetToCenter()
            }
        }
    }

    // MARK: - 布局初始化
    private func setupLayoutIfNeeded() {
        if cachedLayouts.isEmpty || cachedLayouts.count != group.photos.count {
            cachedLayouts = FreeformCanvasLayoutEngine.generateLayout(
                photos: group.photos
            )
        }
    }

    // MARK: - 画布背景色
    private var canvasBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.09)
            : Color(red: 0.96, green: 0.956, blue: 0.941)
    }

    // MARK: - 2D 画布内容
    private func canvasContent(viewportSize: CGSize) -> some View {
        ZStack {
            // 0. 画布正中心回忆焦点卡片 (居于世界坐标原点 (0, 0))
            centerMemoryHeaderCard

            // 1. 照片卡片阵列 (围绕中心回忆标题阿基米德螺旋发散排布)
            ForEach(visibleLayouts) { layout in
                let isTossed = tossingPhotoIDs.contains(layout.id)

                polaroidCard(layout: layout)
                    .rotationEffect(isTossed ? Angle(degrees: layout.rotationAngle.degrees + 45) : layout.rotationAngle)
                    .scaleEffect(isTossed ? 0.12 : 1.0)
                    .offset(
                        x: layout.position.x + (isTossed ? 220 / effectiveScale : 0),
                        y: layout.position.y + (isTossed ? -450 / effectiveScale : 0)
                    )
                    .opacity(isTossed ? 0.0 : 1.0)
                    .animation(.interpolatingSpring(stiffness: 180, damping: 20), value: isTossed)
                    .onTapGesture {
                        handleTapPhotoCard(layout.photo)
                    }
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .offset(effectiveOffset)
        .scaleEffect(effectiveScale, anchor: .center)
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .updating($gestureZoom) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        zoomScale = max(0.55, min(2.3, zoomScale * value))
                    },
                DragGesture(minimumDistance: 8)
                    .updating($gesturePan) { value, state, _ in
                        state = CGSize(
                            width: value.translation.width / effectiveScale,
                            height: value.translation.height / effectiveScale
                        )
                    }
                    .onEnded { value in
                        panOffset.width += value.translation.width / effectiveScale
                        panOffset.height += value.translation.height / effectiveScale
                    }
            )
        )
        .onTapGesture(count: 2) {
            // 双击空白处平滑复位居中视野
            resetToCenter()
        }
    }

    // MARK: - 复位居中视野（定位按钮与双击共用）
    private func resetToCenter() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            zoomScale = 1.0
            panOffset = .zero
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - 单张相纸拟物卡片（全幅等比铺满，彻底去除拍立得底部白色留白）
    private func polaroidCard(layout: CanvasPhotoLayout) -> some View {
        AssetImage(
            asset: layout.photo.asset,
            targetSize: CGSize(width: layout.size.width * 2, height: layout.size.height * 2),
            contentMode: .fill,
            placeholderColor: Color(UIColor.secondarySystemFill)
        )
        .frame(width: layout.size.width, height: layout.size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.22) : Color.white,
                    lineWidth: 3.0
                )
        )
        // 双层拟物阴影：贴合接触阴影 + 发散立体悬浮阴影
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1),
            radius: 6,
            x: 0,
            y: 3
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.16),
            radius: 24,
            x: 0,
            y: 14
        )
    }

    // MARK: - 点击照片卡片交互
    private func handleTapPhotoCard(_ photo: PhotoAsset) {
        // 若为已收藏照片，阻断并弹出原有提示
        if photoManager.isFavorite(photo) {
            onBlocked()
            return
        }

        // 触觉与音效反馈
        SoundManager.playSwipeDelete()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // 触发飞向废纸篓动效
        tossingPhotoIDs.insert(photo.id)

        // 延迟入站并弹出撤销浮条
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            photoManager.addToTrash(photo)
            lastTrashedPhoto = photo

            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showUndoToast = true
            }

            // 3.5 秒后自动隐去撤销浮条
            undoDismissTimer?.cancel()
            undoDismissTimer = Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showUndoToast = false
                        }
                    }
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            tossingPhotoIDs.remove(photo.id)
        }
    }

    // MARK: - 撤销逻辑
    private func undoLastTrash() {
        guard let photo = lastTrashedPhoto else { return }
        undoDismissTimer?.cancel()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        photoManager.restoreFromTrash(photo.id)
        lastTrashedPhoto = nil

        withAnimation(.easeInOut(duration: 0.2)) {
            showUndoToast = false
        }
    }

    // MARK: - 悬浮顶部引导胶囊（带关闭按钮，关闭后持久化不再弹出）
    private var floatingGuidePill: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Text(String(localized: "Pan & pinch to explore · Tap photo to delete"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.primary)

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    hasDismissedCanvasGuide = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.88))
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        )
    }

    // MARK: - 画布中心回忆聚焦点（纯文本裸排，去除背景托底与外框）
    private var centerMemoryHeaderCard: some View {
        VStack(spacing: 4) {
            Text(formattedDateText)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(memorySubtitleText)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .allowsHitTesting(false)
    }

    private var memorySubtitleText: String {
        let count = visibleLayouts.count
        let countText = String(format: String(localized: "%lld photos"), count)
        if totalSizeText.isEmpty {
            return countText
        } else {
            return "\(countText) · \(totalSizeText)"
        }
    }

    private func calculateSize() {
        totalSizeText = SizeCache.load("onthisday_\(group.id)") ?? ""
        let assets = group.photos.map(\.asset)
        Task {
            let totalSize = await Task.detached(priority: .utility) {
                await PHAssetSizeHelper.calculateTotalSize(for: assets)
            }.value
            SizeCache.save("onthisday_\(group.id)", size: totalSize)
            let newText = ByteFormatter.format(totalSize)
            if newText != totalSizeText {
                await MainActor.run {
                    totalSizeText = newText
                }
            }
        }
    }

    private var formattedDateText: String {
        let date = group.photos.first?.asset.creationDate ?? Date()
        if group.isMonthFallback {
            return date.formatted(.dateTime.month())
        } else {
            return date.formatted(.dateTime.month().day())
        }
    }

    // MARK: - 底部撤销 Toast 浮条
    private var undoToastView: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 24))

            Text(String(localized: "Moved to Pending Photos"))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Spacer()

            Button {
                undoLastTrash()
            } label: {
                Text(String(localized: "Undo"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 16, y: 6)
    }

    // MARK: - 今日照片全部移入空态
    private var allDoneEmptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, design: .rounded))
                .foregroundColor(Color.accentColor)

            Text(String(localized: "All Done for Today"))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(.primary)

            Text(String(localized: "All photos have been moved to Pending Photos."))
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
