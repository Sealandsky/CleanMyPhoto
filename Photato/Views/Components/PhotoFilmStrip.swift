import SwiftUI
import Photos

// MARK: - Photo Film Strip
/// 详情页大图下方的缩略图条：水平滚动展示当前批次全部素材，
/// 当前项高亮描边并自动居中；点击缩略图直接跳转对应素材
/// （宿主写入 currentPhotoID，DraggablePhotoView 已有的
/// onChange(of: currentPhotoID) 机制同步 localIndex 完成切换）。
struct PhotoFilmStrip: View {
    let photos: [PhotoAsset]
    let currentPhotoID: String
    var onSelect: (PhotoAsset) -> Void

    /// 缩略图统一基准高度
    static let thumbHeight: CGFloat = 40
    /// 非选中项宽度（固定 3:4 竖图比例：40 * 0.75 = 30pt）
    static let unselectedWidth: CGFloat = 30
    /// 选中项静止宽度（正方形 1:1 比例：40 * 1.0 = 40pt）
    static let selectedWidth: CGFloat = 40
    /// 缩略图条普通间距（紧凑胶卷风格）
    static let spacing: CGFloat = 2.5
    /// 选中项两侧专属呼吸间隙（静止时留白 9pt，拖动时收起为 0）
    static let selectedMargin: CGFloat = 9.0
    /// 垂直内边距（上下各 14pt，确保上下板块间距绝对对称）
    static let verticalPadding: CGFloat = 14

    /// 布局总高度（40pt 缩略图 + 上下对称内边距 28pt = 68pt）
    static let layoutHeight: CGFloat = thumbHeight + verticalPadding * 2

    // 默认步长（全收起 3:4 状态下各相邻项中心距：30 + 2.5 = 32.5pt）
    private static let stepNormal: CGFloat = unselectedWidth + spacing
    // 静止时选中项中心与相邻项中心的间距：20 + 9 + 2.5 + 15 = 46.5pt
    private static let stepFirstIdle: CGFloat = selectedWidth / 2 + selectedMargin + spacing + unselectedWidth / 2

    @State private var isDragging: Bool = false
    @State private var dragTranslation: CGFloat = 0
    @State private var dragStartIndex: Int = 0
    @State private var internalIndex: Int = 0
    @State private var lastHapticIndex: Int = -1
    private let feedback = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width > 0 ? geo.size.width : ScreenSizeHelper.screenSize.width
            let c = activeIndex
            let currentCenter = currentCenterIndex

            ZStack {
                Color.clear

                let visibleRange = getVisibleRange(center: currentCenter)
                ForEach(visibleRange, id: \.self) { i in
                    let photo = photos[i]
                    let isCurrent = (i == c && !isDragging)
                    let xOffset = xOffsetFor(index: i, activeIndex: c, isDragging: isDragging)

                    stripCell(photo, isCurrent: isCurrent, isDragging: isDragging)
                        .offset(x: xOffset)
                        .zIndex(isCurrent ? 1 : 0)
                        .onTapGesture {
                            selectIndex(i)
                        }
                }
            }
            .frame(width: containerWidth, height: Self.thumbHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
            .padding(.vertical, Self.verticalPadding)
        }
        .frame(height: Self.layoutHeight)
        .clipped()
        .onAppear {
            syncIndexWithCurrentPhotoID()
        }
        .onChange(of: currentPhotoID) { _, _ in
            guard !isDragging else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                syncIndexWithCurrentPhotoID()
            }
        }
    }

    // MARK: - Indices & Offsets

    private var activeIndex: Int {
        if let idx = photos.firstIndex(where: { $0.id == currentPhotoID }) {
            return idx
        }
        return min(max(0, internalIndex), max(0, photos.count - 1))
    }

    /// 拖拽进行中当前位于屏幕中轴线的图片索引
    private var currentCenterIndex: Int {
        guard isDragging, !photos.isEmpty else { return activeIndex }
        let indexDelta = Int(round(-dragTranslation / Self.stepNormal))
        return min(max(0, dragStartIndex + indexDelta), photos.count - 1)
    }

    private func getVisibleRange(center: Int) -> ClosedRange<Int> {
        guard !photos.isEmpty else { return 0...(-1) }
        let low = max(0, center - 15)
        let high = min(photos.count - 1, center + 15)
        return low <= high ? low...high : 0...0
    }

    /// 每个缩略图的 X 偏移量：
    /// - 拖拽中：以 dragStartIndex 为纯线性基准点，位置严格等于 (i - dragStartIndex) * 32.5 + dragTranslation，绝无跳动与抖动！
    /// - 静止时：当前项严格居中（offset 0），两侧展现 11.5pt 大留白。
    private func xOffsetFor(index: Int, activeIndex: Int, isDragging: Bool) -> CGFloat {
        if isDragging {
            return CGFloat(index - dragStartIndex) * Self.stepNormal + dragTranslation
        } else {
            if index == activeIndex {
                return 0
            } else if index > activeIndex {
                return Self.stepFirstIdle + CGFloat(index - (activeIndex + 1)) * Self.stepNormal
            } else {
                return -(Self.stepFirstIdle + CGFloat((activeIndex - 1) - index) * Self.stepNormal)
            }
        }
    }

    // MARK: - Interactions

    private func selectIndex(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        internalIndex = index
        feedback.selectionChanged()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            dragTranslation = 0
            onSelect(photos[index])
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard !photos.isEmpty else { return }
        if !isDragging {
            dragStartIndex = activeIndex
            lastHapticIndex = dragStartIndex
            withAnimation(.easeInOut(duration: 0.12)) {
                isDragging = true
            }
        }

        // 阻尼系数（滑出首尾边界时产生平滑弹性阻尼）
        var translation = value.translation.width
        let minTranslation = CGFloat(-(photos.count - 1 - dragStartIndex)) * Self.stepNormal
        let maxTranslation = CGFloat(dragStartIndex) * Self.stepNormal

        if translation > maxTranslation {
            let over = translation - maxTranslation
            translation = maxTranslation + over * 0.3
        } else if translation < minTranslation {
            let over = translation - minTranslation
            translation = minTranslation + over * 0.3
        }

        dragTranslation = translation

        // 纯线性无抖动步进：按移动距离直接推算中轴线索引
        let indexDelta = Int(round(-translation / Self.stepNormal))
        let targetIndex = min(max(0, dragStartIndex + indexDelta), photos.count - 1)

        if targetIndex != lastHapticIndex {
            lastHapticIndex = targetIndex
            internalIndex = targetIndex
            feedback.selectionChanged()
            onSelect(photos[targetIndex])
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        guard !photos.isEmpty else { return }

        // 计算落点索引（支持轻度高速挥弹惯性 step 1 张）
        let velocityX = value.velocity.width
        let indexDelta = Int(round(-dragTranslation / Self.stepNormal))
        var finalIndex = min(max(0, dragStartIndex + indexDelta), photos.count - 1)

        if velocityX < -450 && finalIndex < photos.count - 1 {
            finalIndex += 1
        } else if velocityX > 450 && finalIndex > 0 {
            finalIndex -= 1
        }

        internalIndex = finalIndex
        onSelect(photos[finalIndex])

        // 放手动画：平滑恢复静止态（中间变正方形、两边展开留白、描边浮现）
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isDragging = false
            dragTranslation = 0
        }
    }

    private func syncIndexWithCurrentPhotoID() {
        if let idx = photos.firstIndex(where: { $0.id == currentPhotoID }) {
            internalIndex = idx
            dragStartIndex = idx
        }
    }

    // MARK: - Cell

    private func stripCell(_ photo: PhotoAsset, isCurrent: Bool, isDragging: Bool) -> some View {
        let width = isCurrent ? Self.selectedWidth : Self.unselectedWidth

        return AssetImage(
            asset: photo.asset,
            targetSize: CGSize(width: 120, height: 120),
            contentMode: .fill
        )
        .frame(width: width, height: Self.thumbHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            mediaBadge(photo)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .opacity(isCurrent ? 1.0 : (isDragging ? 0.95 : 0.88))
    }

    /// 视频/LivePhoto 角标：小尺寸半透明底衬托，白字保证任意缩略图上可读
    @ViewBuilder
    private func mediaBadge(_ photo: PhotoAsset) -> some View {
        let symbolName: String? = photo.mediaType == .video
            ? "play.fill"
            : (photo.mediaType == .livePhoto ? "livephoto" : nil)
        if let symbolName {
            Image(systemName: symbolName)
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(.white)
                .padding(2.5)
                .background(Color.black.opacity(0.5), in: Circle())
                .padding(2)
        }
    }
}
