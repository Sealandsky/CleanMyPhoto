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
    /// 选中项宽度（正方形 1:1 比例：40 * 1.0 = 40pt）
    static let selectedWidth: CGFloat = 40
    /// 缩略图条普通间距（紧凑胶卷风格）
    static let spacing: CGFloat = 2.5
    /// 选中项两侧专属呼吸间隙（确保选中项两边有明显留白脱出）
    static let selectedMargin: CGFloat = 9.0
    /// 垂直内边距（上下各 14pt，确保上下板块间距绝对对称）
    static let verticalPadding: CGFloat = 14

    /// 布局总高度（40pt 缩略图 + 上下对称内边距 28pt = 68pt）
    static let layoutHeight: CGFloat = thumbHeight + verticalPadding * 2

    // 选中项中轴到相邻项中轴距离：20 + 9 + 2.5 + 15 = 46.5pt
    private static let stepFirst: CGFloat = selectedWidth / 2 + selectedMargin + spacing + unselectedWidth / 2
    // 非选中相邻项中轴距离：30 + 2.5 = 32.5pt
    private static let stepNormal: CGFloat = unselectedWidth + spacing

    @State private var dragOffset: CGFloat = 0
    @State private var accumulatedDrag: CGFloat = 0
    @State private var internalIndex: Int = 0
    private let feedback = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width > 0 ? geo.size.width : ScreenSizeHelper.screenSize.width
            let c = activeIndex

            ZStack {
                Color.clear

                let visibleRange = getVisibleRange(center: c)
                ForEach(visibleRange, id: \.self) { i in
                    let photo = photos[i]
                    let isCurrent = i == c
                    let xOffset = xOffsetFor(index: i, activeIndex: c) + dragOffset

                    stripCell(photo, isCurrent: isCurrent)
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
            syncIndexWithCurrentPhotoID()
        }
    }

    // MARK: - Layout & Index Calculation

    /// 当前激活的照片索引（始终以 currentPhotoID 为准，找不到时兜底 internalIndex）
    private var activeIndex: Int {
        if let idx = photos.firstIndex(where: { $0.id == currentPhotoID }) {
            return idx
        }
        return min(max(0, internalIndex), max(0, photos.count - 1))
    }

    /// 仅渲染视口及周边缓冲范围内的图片，降低图层与内存开销
    private func getVisibleRange(center: Int) -> ClosedRange<Int> {
        guard !photos.isEmpty else { return 0...(-1) }
        let low = max(0, center - 15)
        let high = min(photos.count - 1, center + 15)
        return low <= high ? low...high : 0...0
    }

    /// 严格以屏幕中轴（offset 0）为基准计算各图片位置：
    /// 当前项永远处于 offset 0（屏幕正中）；
    /// 相邻两侧项预留 stepFirst 距离，呈现自然的大留白；其后项按 stepNormal 紧密排列
    private func xOffsetFor(index: Int, activeIndex: Int) -> CGFloat {
        if index == activeIndex {
            return 0
        } else if index > activeIndex {
            return Self.stepFirst + CGFloat(index - (activeIndex + 1)) * Self.stepNormal
        } else {
            return -(Self.stepFirst + CGFloat((activeIndex - 1) - index) * Self.stepNormal)
        }
    }

    // MARK: - Interactions

    /// 点击某缩略图：平滑弹簧滑入屏幕中央，即时切换素材
    private func selectIndex(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        internalIndex = index
        feedback.selectionChanged()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            dragOffset = 0
            accumulatedDrag = 0
            onSelect(photos[index])
        }
    }

    /// 左右拖动底片：实时跟手拖拽，越过步长阈值即时步进切图，无惯性漂移
    private func handleDragChanged(_ value: DragGesture.Value) {
        guard !photos.isEmpty else { return }
        var currentDrag = value.translation.width - accumulatedDrag
        let step = Self.stepNormal
        let threshold = step * 0.7

        var updated = false
        while currentDrag < -threshold && activeIndex < photos.count - 1 {
            accumulatedDrag -= step
            currentDrag = value.translation.width - accumulatedDrag
            let nextIndex = activeIndex + 1
            internalIndex = nextIndex
            onSelect(photos[nextIndex])
            updated = true
        }

        while currentDrag > threshold && activeIndex > 0 {
            accumulatedDrag += step
            currentDrag = value.translation.width - accumulatedDrag
            let prevIndex = activeIndex - 1
            internalIndex = prevIndex
            onSelect(photos[prevIndex])
            updated = true
        }

        if updated {
            feedback.selectionChanged()
        }
        dragOffset = currentDrag
    }

    /// 拖动释放：停止在当前已选中的图片，弹簧平滑吸附回中轴线，绝不乱切到其他图
    private func handleDragEnded(_ value: DragGesture.Value) {
        accumulatedDrag = 0
        let velocityX = value.velocity.width
        let predictedX = value.predictedEndTranslation.width

        // 仅在明确的高速轻扫划手势下，才额外步进 1 张
        if velocityX < -400 || predictedX < -60 {
            let nextIndex = min(activeIndex + 1, photos.count - 1)
            if nextIndex != activeIndex {
                internalIndex = nextIndex
                feedback.selectionChanged()
                onSelect(photos[nextIndex])
            }
        } else if velocityX > 400 || predictedX > 60 {
            let prevIndex = max(activeIndex - 1, 0)
            if prevIndex != activeIndex {
                internalIndex = prevIndex
                feedback.selectionChanged()
                onSelect(photos[prevIndex])
            }
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
            dragOffset = 0
        }
    }

    private func syncIndexWithCurrentPhotoID() {
        if let idx = photos.firstIndex(where: { $0.id == currentPhotoID }) {
            internalIndex = idx
        }
    }

    // MARK: - Cell

    /// 单个缩略图：选中的用正方形（40x40），非选中的保持 3:4 竖照（30x40）
    private func stripCell(_ photo: PhotoAsset, isCurrent: Bool) -> some View {
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
        // 当前项高亮描边：贴合 4pt 圆角的高对比度 2pt 主色描边
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .opacity(isCurrent ? 1.0 : 0.88)
        .animation(.easeInOut(duration: 0.18), value: isCurrent)
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
