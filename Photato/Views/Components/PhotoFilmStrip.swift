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
    /// 缩略图条间距（紧凑胶卷风格）
    static let itemSpacing: CGFloat = 2.5
    /// 垂直内边距（上下各 14pt，确保上下板块间距绝对对称）
    static let verticalPadding: CGFloat = 14

    /// 布局总高度（40pt 缩略图 + 上下对称内边距 28pt = 68pt）
    static let layoutHeight: CGFloat = thumbHeight + verticalPadding * 2

    @State private var isProgrammaticScroll = false
    @State private var lastFeedbackIndex: Int = -1
    @State private var programmaticResetTask: Task<Void, Never>? = nil
    private let feedback = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width > 0 ? geo.size.width : ScreenSizeHelper.screenSize.width
            // 首尾边距使得首张（index 0）与末张均可精确居中于屏幕中轴线
            let horizontalInset = max(0, (containerWidth - Self.selectedWidth) / 2)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Self.itemSpacing) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            stripCell(photo, at: index, proxy: proxy)
                                .id(photo.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.leading, horizontalInset)
                    .padding(.trailing, horizontalInset)
                    .padding(.vertical, Self.verticalPadding)
                }
                .scrollTargetBehavior(.viewAligned)
                // 拖动底片时实时感知滚动位移，即时切换对应的中轴线照片
                .onScrollGeometryChange(for: CGFloat.self) { scrollGeo in
                    scrollGeo.contentOffset.x
                } action: { _, newOffset in
                    handleScrollOffset(newOffset)
                }
                // 外部切换（如大图手势翻页）时联动居中当前项
                .onChange(of: currentPhotoID) { _, newID in
                    handleExternalPhotoChange(newID, proxy: proxy)
                }
                .onAppear {
                    scrollToInitialPhoto(proxy: proxy)
                }
            }
        }
        .frame(height: Self.layoutHeight)
    }

    // MARK: - Interactions

    /// 点击缩略图：切换选中、触感反馈、平滑滚至屏幕居中
    private func selectPhoto(_ photo: PhotoAsset, at index: Int, proxy: ScrollViewProxy) {
        lastFeedbackIndex = index
        beginProgrammaticScroll()
        onSelect(photo)
        feedback.selectionChanged()
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(photo.id, anchor: .center)
        }
    }

    /// 拖动底片手势流转：按步长换算落点索引并即时切换
    private func handleScrollOffset(_ offset: CGFloat) {
        guard !isProgrammaticScroll, !photos.isEmpty else { return }
        let step = Self.unselectedWidth + Self.itemSpacing
        let rawIndex = Int(round(offset / step))
        let targetIndex = min(max(0, rawIndex), photos.count - 1)
        if targetIndex != lastFeedbackIndex {
            lastFeedbackIndex = targetIndex
            let targetPhoto = photos[targetIndex]
            if targetPhoto.id != currentPhotoID {
                onSelect(targetPhoto)
                feedback.selectionChanged()
            }
        }
    }

    /// 外部大图翻页触发的平滑滚动居中
    private func handleExternalPhotoChange(_ newID: String, proxy: ScrollViewProxy) {
        guard !newID.isEmpty else { return }
        // 若当前变更正是底片滚动自己触发的，避免向 proxy 发出重复打断指令
        if photos.indices.contains(lastFeedbackIndex) && photos[lastFeedbackIndex].id == newID {
            return
        }
        if let index = photos.firstIndex(where: { $0.id == newID }) {
            lastFeedbackIndex = index
        }
        beginProgrammaticScroll()
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(newID, anchor: .center)
        }
    }

    private func beginProgrammaticScroll() {
        programmaticResetTask?.cancel()
        isProgrammaticScroll = true
        programmaticResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                isProgrammaticScroll = false
            }
        }
    }

    private func scrollToInitialPhoto(proxy: ScrollViewProxy) {
        guard !currentPhotoID.isEmpty else { return }
        if let index = photos.firstIndex(where: { $0.id == currentPhotoID }) {
            lastFeedbackIndex = index
        }
        DispatchQueue.main.async {
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(currentPhotoID, anchor: .center)
            }
        }
    }

    // MARK: - Cell

    /// 单个缩略图：选中的用正方形（40x40），非选中的保持 3:4 竖照（30x40）
    private func stripCell(_ photo: PhotoAsset, at index: Int, proxy: ScrollViewProxy) -> some View {
        let isCurrent = photo.id == currentPhotoID
        let width = isCurrent ? Self.selectedWidth : Self.unselectedWidth

        return Button {
            selectPhoto(photo, at: index, proxy: proxy)
        } label: {
            AssetImage(
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
        .buttonStyle(.plain)
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
