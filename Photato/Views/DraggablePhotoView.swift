
import SwiftUI
import Photos
import UIKit

struct DraggablePhotoView: View {
    let photos: [PhotoAsset]
    var currentPhotoID: String
    let onPhotoChange: (String, Int) -> Void
    var onDelete: ((PhotoAsset) -> Void)?
    var onBlockedDelete: (() -> Void)?
    let onDismiss: () -> Void
    let screenSize: CGSize
    let photoSpacing: CGFloat = 12
    var isFavorite: ((PhotoAsset) -> Bool)? = nil
    /// 展开目标区 global frame（详情卡片 ↔ 全屏连续展开的终点：导航栏下安全区），
    /// 仅 embedded 模式使用；为零则不启用展开
    var expandTargetFrame: CGRect = .zero
    /// 展开进度 0~1（页面级联动：黑底淡入/其余区块淡出/禁滚动），
    /// 由本组件的展开状态机驱动（捏合跟手逐帧写、动画吸附随动画写）
    var expandProgress: Binding<CGFloat> = .constant(0)
    /// 是否处于缩略图快速滑动/拖动预览中（拖动中仅解码轻量缩略图、暂缓视频播放器创建，杜绝内存峰值与卡顿）
    var isScrubbing: Bool = false

    /// 卡片版式：fullScreen = 独立全屏页（默认，上下各留 120pt 给页面操作栏）；
    /// embeddedSection = 作为详情页垂直版式中的预览区嵌入（支持卡片 ↔ 全屏连续展开）
    enum CardPresentation {
        case fullScreen
        case embeddedSection
    }
    var cardPresentation: CardPresentation = .fullScreen

    private var effectiveCardTopPadding: CGFloat {
        cardPresentation == .fullScreen ? cardTopPadding : 0
    }
    private var effectiveCardBottomPadding: CGFloat {
        cardPresentation == .fullScreen ? cardBottomPadding : 0
    }

    @State private var localIndex: Int
    @State private var offset: CGSize = .zero
    @State private var isDragging = false
    @State private var isNavigating = false
    @State private var navigationID: UInt = 0
    @State private var deleteID: UInt = 0
    @State private var hasTriggeredHaptic = false
    @State private var isDeleteTransitioning = false
    @Binding var deleteTrigger: Int

    // MARK: 展开状态机（详情卡片 ↔ 全屏；参考系统相册：单视图连续缩放，跟手无「切换页面」感）
    /// 展开显示图宽：nil = 详情卡片基准；非 nil = 当前展开到的图宽
    /// （捏合逐帧驱动，松手按阈值吸附，动画驱动单击/双击路径）
    @State private var expandWidth: CGFloat? = nil
    /// 捏合手势上一帧倍率（增量式计算，手势结束置 nil）
    @State private var lastMagnification: CGFloat?
    /// 展开态（超过全屏宽）的双轴平移偏移
    @State private var zoomOffset: CGSize = .zero
    /// 平移手势起始时的偏移基准
    @State private var zoomPanBase: CGSize = .zero
    /// 放大态平移进行中（手势起始标记）
    @State private var isZoomPanning = false
    /// 卡片容器实际尺寸（GeometryReader 采集）
    @State private var cardContainerSize: CGSize = .zero
    /// 容器 global frame（展开中心插值用）
    @State private var containerGlobalFrame: CGRect = .zero
    private let maxZoomScale: CGFloat = 4
    private let doubleTapZoomScale: CGFloat = 2.5

    // 卡片样式配置（和你截图匹配）
    private let cardCornerRadius: CGFloat = 24
    private let cardPadding: CGFloat = 16
    private let cardTopPadding: CGFloat = 120
    private let cardBottomPadding: CGFloat = 120
    private let cardShadowRadius: CGFloat = 16
    private let cardShadowOpacity: CGFloat = 0.15
    private let dismissThreshold: CGFloat = 60
    private let deleteThreshold: CGFloat = 80

    private var safeIndex: Int {
        photos.isEmpty ? 0 : min(max(localIndex, 0), photos.count - 1)
    }

    private var currentPhoto: PhotoAsset { photos[safeIndex] }
    private var isCurrentPhotoFavorite: Bool {
        isFavorite?(currentPhoto) ?? currentPhoto.isFavorite
    }
    private var previousPhoto: PhotoAsset? { safeIndex > 0 ? photos[safeIndex - 1] : nil }
    private var nextPhoto: PhotoAsset? { safeIndex < photos.count - 1 ? photos[safeIndex + 1] : nil }

    init(
        photos: [PhotoAsset],
        currentPhotoID: String,
        isScrubbing: Bool = false,
        deleteTrigger: Binding<Int>,
        onPhotoChange: @escaping (String, Int) -> Void,
        onDelete: ((PhotoAsset) -> Void)? = nil,
        onBlockedDelete: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void,
        screenSize: CGSize,
        cardPresentation: CardPresentation = .fullScreen,
        isFavorite: ((PhotoAsset) -> Bool)? = nil,
        expandTargetFrame: CGRect = .zero,
        expandProgress: Binding<CGFloat> = .constant(0)
    ) {
        self.photos = photos
        self.currentPhotoID = currentPhotoID
        self.isScrubbing = isScrubbing
        self._deleteTrigger = deleteTrigger
        self.onPhotoChange = onPhotoChange
        self.onDelete = onDelete
        self.onBlockedDelete = onBlockedDelete
        self.onDismiss = onDismiss
        self.screenSize = screenSize
        self.cardPresentation = cardPresentation
        self.isFavorite = isFavorite
        self.expandTargetFrame = expandTargetFrame
        self.expandProgress = expandProgress
        let idx = photos.firstIndex(where: { $0.id == currentPhotoID }) ?? 0
        _localIndex = State(initialValue: idx)
    }

    var body: some View {
        gestureContainer
    }

    /// 手势挂载（全部静态挂载，模式差异仅在 handler 内路由）：
    /// - 详情页（embedded）：单击进/出全屏、双击放大进入、双指捏合跟手展开、
    ///   放大态拖动平移、全屏态下拉收拢、左右滑切页（纵向让权外层 ScrollView）
    /// - fullScreen（遗留独立页）：拖动删除/关闭/切页
    @ViewBuilder
    private var gestureContainer: some View {
        if cardPresentation == .embeddedSection {
            cardStack
                .gesture(
                    DirectionalHorizontalPanGesture(
                        onChanged: { translation in
                            handleHorizontalPanChanged(translation: translation)
                        },
                        onEnded: { translation, velocity in
                            handleHorizontalPanEnded(translation: translation, velocity: velocity)
                        }
                    )
                )
                .gesture(
                    SingleDoubleTapGesture(
                        onSingle: handleSingleTap,
                        onDouble: handleDoubleTap
                    )
                )
                .gesture(
                    ZoomPanGesture(
                        isZoomEnabled: {
                            (expandWidth ?? cardImageWidth) > fullImageWidth * 1.02
                                || expandProgress.wrappedValue > 0.5
                        },
                        onChanged: { translation in
                            if isExpandZoomed {
                                handleZoomPanChanged(translation: CGSize(width: translation.x, height: translation.y))
                            } else {
                                handleCollapseDragChanged(translation: CGSize(width: translation.x, height: translation.y))
                            }
                        },
                        onEnded: { _, _ in
                            if isExpandZoomed {
                                handleZoomPanEnded()
                            } else {
                                handleCollapseDragEnded()
                            }
                        }
                    )
                )
                .simultaneousGesture(zoomMagnifyGesture)
        } else {
            cardStack.gesture(dragGesture)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value)
            }
    }

    private var cardStack: some View {
        GeometryReader { geometry in
            let expand = expandGeometry(containerSize: geometry.size)
            let currentProgress = expand?.progress ?? expandProgress.wrappedValue

            ZStack {
                backgroundLayer
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())

                // 仅在手指拖拽或切图动画中渲染相邻卡片；静止闲置时只有当前照片存在，彻底杜绝矮宽图背后透出相邻图片
                if (isDragging || isNavigating || offset != .zero), let prev = previousPhoto, !isDeleteTransitioning {
                    let prevExpand = expandGeometry(for: prev, containerSize: geometry.size, progress: currentProgress)
                    mediaCardLayer(
                        prev,
                        isCurrent: false,
                        containerSize: geometry.size,
                        displaySize: prevExpand?.size,
                        chromeScale: 1 - (prevExpand?.progress ?? 0)
                    )
                    .offset(
                        x: -geometry.size.width - photoSpacing + offset.width + (prevExpand?.offset.width ?? 0),
                        y: offset.height + (prevExpand?.offset.height ?? 0)
                    )
                    .zIndex(0)
                }

                // 当前照片卡片：展开状态机驱动「详情基准 ↔ 全屏」的连续几何插值
                // （尺寸/中心/圆角/阴影随进度变化，参考系统相册单视图缩放规则）
                mediaCardLayer(
                    currentPhoto,
                    isCurrent: true,
                    containerSize: geometry.size,
                    displaySize: expand?.size,
                    chromeScale: 1 - (expand?.progress ?? 0)
                )
                .offset(x: offset.width + (expand?.offset.width ?? 0) + zoomOffset.width,
                        y: offset.height + (expand?.offset.height ?? 0) + zoomOffset.height)
                .zIndex(1)

                // 仅在手指拖拽或切图动画中渲染相邻卡片
                if (isDragging || isNavigating || offset != .zero), let next = nextPhoto {
                    let nextExpand = expandGeometry(for: next, containerSize: geometry.size, progress: currentProgress)
                    mediaCardLayer(
                        next,
                        isCurrent: false,
                        containerSize: geometry.size,
                        displaySize: nextExpand?.size,
                        chromeScale: 1 - (nextExpand?.progress ?? 0)
                    )
                    .offset(
                        x: geometry.size.width + photoSpacing + offset.width + (nextExpand?.offset.width ?? 0),
                        y: offset.height + (nextExpand?.offset.height ?? 0)
                    )
                    .zIndex(0)
                }

                // Delete indicator
                if showDeleteIndicator && onDelete != nil {
                    VStack {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(16)
                            .background(Circle().fill(Color.red.opacity(0.8)))
                        Text(String(localized: "Move to Trash"))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                    }
                    .transition(.opacity)
                    .opacity(offset.height < -deleteThreshold ? 1 : 0.5)
                    .zIndex(10)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // 裁剪边界外扩 20pt：滑动切页的相邻卡仍被裁住，同时保留当前卡投影；
            // 展开态彻底放开裁剪（图要溢出容器铺满全屏）
            .clipShape(Rectangle().inset(by: currentProgress > 0.01 ? -3000 : -20))
            .onAppear {
                cardContainerSize = geometry.size
                containerGlobalFrame = geometry.frame(in: .global)
            }
            .onChange(of: geometry.size) { _, newSize in
                cardContainerSize = newSize
                expandProgress.wrappedValue = expandProgressValue(for: expandWidth ?? cardImageWidth)
            }
            .onChange(of: geometry.frame(in: .global)) { _, frame in
                containerGlobalFrame = frame
            }
        }
        .onChange(of: currentPhotoID) { _, newID in
            guard !isDeleteTransitioning, !isNavigating else { return }
            if let idx = photos.firstIndex(where: { $0.id == newID }) {
                localIndex = idx
                resetZoomStates()
                // 切页保持展开程度（全屏滑切页仍全屏），进度按新照片比例刷新
                if expandProgress.wrappedValue > 0.8 {
                    let newPhoto = photos[idx]
                    expandWidth = Self.fittedSize(ratio: newPhoto.pixelAspectRatio, in: expandTargetFrame.size).width
                    expandProgress.wrappedValue = 1.0
                } else {
                    expandProgress.wrappedValue = expandProgressValue(for: expandWidth ?? cardImageWidth)
                }
            }
        }
        .onChange(of: deleteTrigger) { oldValue, newValue in
            guard newValue > oldValue, onDelete != nil else { return }
            if isCurrentPhotoFavorite {
                onBlockedDelete?()
                return
            }
            DispatchQueue.main.async {
                performDeleteAnimation()
            }
        }
    }

    /// 区块底色：fullScreen 版式统一使用系统分组背景底色（与设置页一致）；
    /// 嵌入/沉浸版式不绘制底色（透出详情页页面底色或沉浸层黑底）
    @ViewBuilder
    private var backgroundLayer: some View {
        if cardPresentation == .fullScreen {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
        } else {
            Color.clear
        }
    }

    // MARK: - Card Size Helper
    /// aspectFit 目标尺寸（static 供外部计算转场几何：详情页卡片图区 ↔ 全屏图区）
    static func fittedSize(ratio: CGFloat, in available: CGSize) -> CGSize {
        guard available.width > 0, available.height > 0 else { return .zero }
        let containerRatio = available.width / available.height
        if containerRatio > ratio {
            let h = available.height
            let w = min(h * ratio, available.width)
            return CGSize(width: w, height: h)
        } else {
            let w = available.width
            let h = min(w / max(ratio, 0.01), available.height)
            return CGSize(width: w, height: h)
        }
    }

    private func cardSize(for photoAsset: PhotoAsset, in available: CGSize) -> CGSize {
        Self.fittedSize(ratio: photoAsset.pixelAspectRatio, in: available)
    }

    /// 详情页大图目标尺寸：采用屏幕物理像素加载高清大图，滑动速览时使用轻量缩略图防内存峰值
    private var cardTargetSize: CGSize {
        isScrubbing ? ScreenSizeHelper.cardThumbnailSize : ScreenSizeHelper.screenPhysicalSize
    }

    // MARK: - Media Card Layer（当前卡片与相邻卡片共用统一视图骨架，杜绝切图瞬间视图替换闪烁与卡顿）
    /// - displaySize：展开态的图尺寸（nil = 详情基准 aspectFit 尺寸）
    /// - chromeScale：卡片外观（圆角/描边/阴影）保留比例，展开进度驱动 1→0
    @ViewBuilder
    private func mediaCardLayer(
        _ photoAsset: PhotoAsset,
        isCurrent: Bool,
        containerSize: CGSize,
        displaySize: CGSize? = nil,
        chromeScale: CGFloat = 1
    ) -> some View {
        let available = CGSize(
            width: max(0, containerSize.width - cardPadding * 2),
            height: max(0, containerSize.height - effectiveCardTopPadding - effectiveCardBottomPadding)
        )
        let size = displaySize ?? cardSize(for: photoAsset, in: available)
        let radius = cardCornerRadius * chromeScale
        let strokeOpacity = 0.1 * chromeScale
        let shadowOpacity = cardShadowOpacity * chromeScale
        let shadowRadius = cardShadowRadius * chromeScale
        let imageSize = cardTargetSize

        switch photoAsset.mediaType {
        case .video:
            let content = ZStack {
                AssetImage(
                    asset: photoAsset.asset,
                    targetSize: imageSize,
                    contentMode: .fit,
                    highQuality: !isScrubbing,
                    placeholderColor: Color(UIColor.secondarySystemFill)
                )
                .frame(width: size.width, height: size.height)

                if isCurrent && !isScrubbing {
                    // 视频区域点按由播放器内部 SwiftUI 手势承担（与控件条按钮
                    // 天然互斥）：与单击同语义——详情态进全屏、全屏态退出
                    VideoPlayerView(
                        asset: photoAsset.asset,
                        isDragging: $isDragging,
                        onAreaTap: { handleVideoAreaTap() }
                    )
                    .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)

            applyCardChrome(
                to: content,
                radius: radius,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius
            )
            .frame(width: containerSize.width, height: containerSize.height)
            .id(photoAsset.id)

        case .livePhoto:
            let content = ZStack {
                AssetImage(
                    asset: photoAsset.asset,
                    targetSize: imageSize,
                    contentMode: .fit,
                    highQuality: !isScrubbing,
                    placeholderColor: Color(UIColor.secondarySystemFill)
                )
                .frame(width: size.width, height: size.height)

                if isCurrent && !isScrubbing {
                    LivePhotoPlayerView(asset: photoAsset.asset)
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)

            applyCardChrome(
                to: content,
                radius: radius,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius
            )
            .frame(width: containerSize.width, height: containerSize.height)
            .id(photoAsset.id)

        default:
            let content = AssetImage(
                asset: photoAsset.asset,
                targetSize: imageSize,
                contentMode: .fit,
                highQuality: !isScrubbing,
                placeholderColor: Color(UIColor.secondarySystemFill)
            )
            .frame(width: size.width, height: size.height)

            applyCardChrome(
                to: content,
                radius: radius,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius
            )
            .frame(width: containerSize.width, height: containerSize.height)
            .id(photoAsset.id)
        }
    }

    /// 卡片外观修饰：全屏态（radius <= 0.001）完全移除圆角裁剪、边框和阴影；卡片态保留圆角与微质感
    @ViewBuilder
    private func applyCardChrome<Content: View>(
        to content: Content,
        radius: CGFloat,
        strokeOpacity: CGFloat,
        shadowOpacity: CGFloat,
        shadowRadius: CGFloat
    ) -> some View {
        if radius > 0.001 {
            content
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 4)
        } else {
            content
        }
    }
    // MARK: - Gesture Handlers
    @State private var showDeleteIndicator = false

    /// 水平单向手势位移回调：驱动卡片横向视差滑动（缩放态由 ZoomPan 接管，忽略）
    private func handleHorizontalPanChanged(translation: CGPoint) {
        if isNavigating || isExpandZoomed { return }
        isDragging = true
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
            offset = CGSize(width: translation.x, height: 0)
        }
    }

    /// 水平单向手势结束回调：判定滑动距离与速度决定是否切图
    private func handleHorizontalPanEnded(translation: CGPoint, velocity: CGPoint) {
        if isNavigating || isExpandZoomed { return }
        horizontalNavigate(horizontal: translation.x, vertical: translation.y, velocity: velocity.x)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        if isNavigating { return }

        let translation = value.translation

        // 垂直流式版式：垂直滑动交给页面滚动，仅水平拖动驱动素材切换
        if cardPresentation == .embeddedSection {
            guard abs(translation.width) > abs(translation.height) else { return }
            isDragging = true
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
                offset = CGSize(width: translation.width, height: 0)
            }
            return
        }

        isDragging = true

        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
            if abs(translation.width) > abs(translation.height) {
                offset = CGSize(width: translation.width, height: 0)
                showDeleteIndicator = false
            } else if translation.height > 0 {
                offset = CGSize(width: 0, height: translation.height)
                showDeleteIndicator = false
            } else {
                offset = CGSize(width: 0, height: translation.height)
                showDeleteIndicator = abs(translation.height) > deleteThreshold
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if isNavigating { return }

        let horizontal = value.translation.width
        let vertical = value.translation.height
        let velocity = value.velocity.width

        // 垂直流式版式：无上滑删除/下滑退出，垂直滑动由页面滚动接管
        if cardPresentation != .embeddedSection {
            // Swipe up to delete
            if vertical < -deleteThreshold && onDelete != nil {
                if isCurrentPhotoFavorite {
                    onBlockedDelete?()
                    resetPosition()
                } else {
                    performDeleteAnimation()
                }
                return
            }

            // Swipe down to dismiss
            if vertical > dismissThreshold {
                performDismissAnimation()
                return
            }
        }

        horizontalNavigate(horizontal: horizontal, vertical: vertical, velocity: velocity)
    }

    // MARK: - 展开状态机（详情卡片 ↔ 全屏；参考系统相册：单视图连续缩放，跟手无切换感）

    /// 展开是否可用（embedded 且目标几何已就位）
    private var expandEnabled: Bool {
        cardPresentation == .embeddedSection
            && expandTargetFrame.width > 0
            && containerGlobalFrame.width > 0
            && cardContainerSize.width > 0
    }

    /// 详情卡片基准图宽（aspectFit 于卡片可用区）
    private var cardImageWidth: CGFloat {
        let avail = CGSize(
            width: cardContainerSize.width - cardPadding * 2,
            height: cardContainerSize.height
        )
        return Self.fittedSize(ratio: currentPhoto.pixelAspectRatio, in: avail).width
    }

    /// 全屏基准图宽（aspectFit 于展开目标区）
    private var fullImageWidth: CGFloat {
        Self.fittedSize(ratio: currentPhoto.pixelAspectRatio, in: expandTargetFrame.size).width
    }

    /// 展开进度（0=卡片基准，1=全屏基准）
    private func expandProgressValue(for width: CGFloat) -> CGFloat {
        let cardW = cardImageWidth
        let fullW = fullImageWidth
        guard cardW > 0, fullW > cardW else {
            return expandWidth != nil ? 1.0 : 0.0
        }
        return min(max((width - cardW) / (fullW - cardW), 0), 1)
    }

    /// 超过全屏宽的放大态（此时拖动=平移，禁水平切页）
    private var isExpandZoomed: Bool {
        (expandWidth ?? cardImageWidth) > fullImageWidth * 1.02
    }

    /// 当前展开几何（渲染插值用）：nil = 详情基准（无展开）
    private struct ExpandGeometry {
        let size: CGSize
        let offset: CGSize
        let progress: CGFloat
    }

    private func expandGeometry(containerSize: CGSize) -> ExpandGeometry? {
        guard expandEnabled, let w = expandWidth, w > 0 else { return nil }
        let ratio = currentPhoto.pixelAspectRatio
        let avail = CGSize(
            width: max(0, containerSize.width - cardPadding * 2),
            height: max(0, containerSize.height - effectiveCardTopPadding - effectiveCardBottomPadding)
        )
        let cardSize = Self.fittedSize(ratio: ratio, in: avail)
        let fullSize = Self.fittedSize(ratio: ratio, in: expandTargetFrame.size)
        guard cardSize.width > 0, fullSize.width > 0 else { return nil }

        let widthDelta = fullSize.width - cardSize.width
        let progress: CGFloat
        if widthDelta > 0.5 {
            let clamped = min(max(w, cardSize.width * 0.85), fullSize.width * maxZoomScale)
            progress = min(max((clamped - cardSize.width) / widthDelta, 0), 1)
        } else {
            progress = min(max(expandProgress.wrappedValue, 0), 1)
        }

        let currentWidth = cardSize.width + widthDelta * progress
        let currentHeight = currentWidth / max(ratio, 0.01)
        let zoomScale = max(1.0, w / max(fullSize.width, 1.0))
        let size = CGSize(width: currentWidth * zoomScale, height: currentHeight * zoomScale)

        // 中心从卡片容器中心插值到全屏目标区中心（global 差值即局部平移量）
        let offset = CGSize(
            width: (expandTargetFrame.midX - containerGlobalFrame.midX) * progress,
            height: (expandTargetFrame.midY - containerGlobalFrame.midY) * progress
        )
        return ExpandGeometry(size: size, offset: offset, progress: progress)
    }

    /// 计算相邻照片在当前展开进度下的几何属性（全屏态下无圆角、无投影描边、尺寸铺满全屏、垂直居中对齐全屏中心）
    private func expandGeometry(for photo: PhotoAsset, containerSize: CGSize, progress: CGFloat) -> ExpandGeometry? {
        guard expandEnabled, progress > 0.001 else { return nil }
        let ratio = photo.pixelAspectRatio
        let avail = CGSize(
            width: max(0, containerSize.width - cardPadding * 2),
            height: max(0, containerSize.height - effectiveCardTopPadding - effectiveCardBottomPadding)
        )
        let cardSize = Self.fittedSize(ratio: ratio, in: avail)
        let fullSize = Self.fittedSize(ratio: ratio, in: expandTargetFrame.size)
        guard cardSize.width > 0, fullSize.width > 0 else { return nil }

        let clampedProgress = min(max(progress, 0), 1)
        let width = cardSize.width + (fullSize.width - cardSize.width) * clampedProgress
        let height = width / max(ratio, 0.01)
        let size = CGSize(width: width, height: height)

        let offset = CGSize(
            width: (expandTargetFrame.midX - containerGlobalFrame.midX) * clampedProgress,
            height: (expandTargetFrame.midY - containerGlobalFrame.midY) * clampedProgress
        )
        return ExpandGeometry(size: size, offset: offset, progress: clampedProgress)
    }

    /// 双指捏合：跟手逐帧更新展开宽度（系统规则——手指张合直接映射图宽，
    /// 无「触发转场」），松手按半程阈值吸附
    private var zoomMagnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let ratioInc: CGFloat
                if let last = lastMagnification {
                    ratioInc = value.magnification / max(last, 0.001)
                } else {
                    ratioInc = 1
                }
                lastMagnification = value.magnification
                guard expandEnabled else { return }

                let base = expandWidth ?? cardImageWidth
                let target = min(
                    max(base * ratioInc, cardImageWidth * 0.85),
                    fullImageWidth * maxZoomScale
                )
                expandWidth = target
                expandProgress.wrappedValue = expandProgressValue(for: target)
            }
            .onEnded { _ in
                lastMagnification = nil
                guard expandEnabled, let w = expandWidth else { return }
                snapExpand(from: w)
            }
    }

    /// 松手吸附：低于半程弹回卡片、半程以上继续到全屏、已达放大态（超全屏宽）保留
    private func snapExpand(from width: CGFloat) {
        let cardW = cardImageWidth
        let fullW = fullImageWidth
        guard fullW > cardW else { return }
        if width >= fullW { return }  // 放大态跟手保留
        let mid = (cardW + fullW) / 2
        animateExpand(to: width < mid ? cardW : fullW)
    }

    /// 动画驱动展开（单击/双击/吸附路径；进度 binding 随同一动画事务联动页面级视觉）
    private func animateExpand(to target: CGFloat) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            expandWidth = target
            expandProgress.wrappedValue = expandProgressValue(for: target)
        }
        if target <= cardImageWidth + 0.5 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                zoomOffset = .zero
            }
        }
    }

    /// 收拢回详情卡片（退出全屏；平移一并复位）
    private func collapseToCard() {
        animateExpand(to: cardImageWidth)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if expandProgress.wrappedValue <= 0.01 {
                expandWidth = nil
            }
        }
    }

    /// 单击：详情态 → 展开到全屏；全屏态 → 收拢回卡片（系统查看器语义）
    private func handleSingleTap() {
        guard expandEnabled else { return }
        // 视频不经过卡片层 recognizer（点控件条按钮会误触发）；
        // 视频区域点按走 VideoPlayerView 内部手势（handleVideoAreaTap）
        guard currentPhoto.mediaType != .video else { return }
        let w = expandWidth ?? cardImageWidth
        if w <= cardImageWidth * 1.02 {
            animateExpand(to: fullImageWidth)
        } else if w >= fullImageWidth * 0.98 {
            collapseToCard()
        }
        // 半程中间态（捏合后未吸附）忽略
    }

    /// 视频区域点按（VideoPlayerView 内部手势路径）：与单击同语义
    private func handleVideoAreaTap() {
        guard expandEnabled else { return }
        let w = expandWidth ?? cardImageWidth
        if w <= cardImageWidth * 1.02 {
            animateExpand(to: fullImageWidth)
        } else if w >= fullImageWidth * 0.98 {
            collapseToCard()
        }
    }

    /// 双击：未达全屏 → 放大进入（全屏×2.5）；全屏放大态 → 还原 1x（toggle）
    private func handleDoubleTap() {
        guard expandEnabled, currentPhoto.mediaType != .video else { return }
        let w = expandWidth ?? cardImageWidth
        let fullW = fullImageWidth
        if w > fullW * 1.05 {
            animateExpand(to: fullW)
        } else {
            animateExpand(to: fullW * doubleTapZoomScale)
        }
    }

    /// 放大态（超全屏宽）双轴平移：实时钳制在放大可视范围内
    private func handleZoomPanChanged(translation: CGSize) {
        guard isExpandZoomed else { return }
        if !isZoomPanning {
            isZoomPanning = true
            zoomPanBase = zoomOffset
        }
        zoomOffset = clampZoomOffset(CGSize(
            width: zoomPanBase.width + translation.width,
            height: zoomPanBase.height + translation.height
        ))
    }

    private func handleZoomPanEnded() {
        guard isExpandZoomed else { return }
        isZoomPanning = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            zoomOffset = clampZoomOffset(zoomOffset)
        }
    }

    /// 平移边界：超全屏的部分可移动（每侧 (z-1)×目标区尺寸/2）
    private func clampZoomOffset(_ target: CGSize) -> CGSize {
        let z = (expandWidth ?? fullImageWidth) / max(fullImageWidth, 1)
        guard z > 1 else { return .zero }
        let maxX = (z - 1) * expandTargetFrame.width / 2
        let maxY = (z - 1) * expandTargetFrame.height / 2
        return CGSize(
            width: min(max(target.width, -maxX), maxX),
            height: min(max(target.height, -maxY), maxY)
        )
    }

    // MARK: 全屏态下拉收拢（跟手）

    /// 下拉收拢的起始宽度基准
    @State private var collapseDragBase: CGFloat?

    private func handleCollapseDragChanged(translation: CGSize) {
        guard expandEnabled else { return }
        if !isZoomPanning {
            isZoomPanning = true
            collapseDragBase = expandWidth ?? fullImageWidth
        }
        guard let base = collapseDragBase else { return }
        // 下拉逐 pt 收窄（跟手），上拉不超过全屏宽
        let target = min(max(base - translation.height * 2, cardImageWidth), fullImageWidth)
        expandWidth = target
        expandProgress.wrappedValue = expandProgressValue(for: target)
    }

    private func handleCollapseDragEnded() {
        isZoomPanning = false
        collapseDragBase = nil
        guard expandEnabled, let w = expandWidth else { return }
        snapExpand(from: w)
    }

    private func resetZoomStates() {
        zoomOffset = .zero
        zoomPanBase = .zero
        isZoomPanning = false
        lastMagnification = nil
    }

    /// 水平滑动切换素材（速度 + 距离双阈值），未达阈值回弹复位
    private func horizontalNavigate(horizontal: CGFloat, vertical: CGFloat, velocity: CGFloat) {
        if abs(horizontal) > abs(vertical) {
            let distanceThreshold = screenSize.width * 0.35
            let velocityThreshold: CGFloat = 500

            let shouldGoForward = horizontal < -distanceThreshold ||
                (horizontal < 0 && velocity < -velocityThreshold)
            let shouldGoBackward = horizontal > distanceThreshold ||
                (horizontal > 0 && velocity > velocityThreshold)

            if shouldGoForward && nextPhoto != nil {
                navigate(direction: .forward)
            } else if shouldGoBackward && previousPhoto != nil {
                navigate(direction: .backward)
            } else {
                resetPosition()
            }
        } else {
            resetPosition()
        }
    }

    // MARK: - Navigate (in-place, no view recreation)
    private enum SwipeDirection { case forward, backward }

    private func navigate(direction: SwipeDirection) {
        guard (direction == .forward && localIndex < photos.count - 1) ||
              (direction == .backward && localIndex > 0) else {
            resetPositionWithBounce()
            return
        }

        let targetIndex = direction == .forward ? localIndex + 1 : localIndex - 1
        let targetPhoto = photos[targetIndex]

        // 切页时复位缩放态（滑走的卡不保留放大）
        resetZoomStates()

        let currentNavID = navigationID + 1
        navigationID = currentNavID
        isNavigating = true

        // 核心丝滑优化：一旦确定切图，在开始滑动的第 0 毫秒立即通知外部
        // 此时 isNavigating 已置为 true，父视图更新 currentPhotoID 不会提前打乱 localIndex
        onPhotoChange(targetPhoto.id, targetIndex)

        let pageStep = screenSize.width + photoSpacing
        withAnimation(.spring(response: 0.32, dampingFraction: 0.92)) {
            offset = direction == .forward
                ? CGSize(width: -pageStep, height: 0)
                : CGSize(width: pageStep, height: 0)
        } completion: {
            guard navigationID == currentNavID else { return }

            localIndex = targetIndex

            if expandProgress.wrappedValue > 0.8 {
                let newFullW = Self.fittedSize(ratio: targetPhoto.pixelAspectRatio, in: expandTargetFrame.size).width
                expandWidth = newFullW
                expandProgress.wrappedValue = 1.0
            }

            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                offset = .zero
                isDragging = false
            }
            isNavigating = false
            hasTriggeredHaptic = false
        }
    }

    // MARK: - Dismiss Animation
    private func performDismissAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(width: 0, height: screenSize.height)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                onDismiss()
            }
        }
    }

    // MARK: - Delete Animation
    private func performDeleteAnimation() {
        triggerConfirmHaptic()
        resetZoomStates()
        expandWidth = nil
        expandProgress.wrappedValue = 0

        let currentDelID = deleteID + 1
        deleteID = currentDelID

        let photoToDelete = currentPhoto
        let nextPhotoRef = nextPhoto
        let prevPhotoRef = previousPhoto
        let hasMore = nextPhotoRef != nil || prevPhotoRef != nil
        let hasForward = nextPhotoRef != nil

        // Step 1: Slide current photo up
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = CGSize(width: 0, height: -screenSize.height)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard deleteID == currentDelID else { return }

            if hasMore {
                isDeleteTransitioning = true

                // Step 2: Delete first, array shrinks, next photo falls into localIndex
                onDelete?(photoToDelete)

                // Step 3: Position off-screen, then slide in
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    if !hasForward, localIndex > 0 {
                        localIndex -= 1
                    }
                    if localIndex >= photos.count {
                        localIndex = max(0, photos.count - 1)
                    }
                    offset = CGSize(width: screenSize.width + photoSpacing, height: 0)
                    isDragging = false
                    showDeleteIndicator = false
                }

                onPhotoChange(currentPhoto.id, localIndex)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.95)) {
                    offset = .zero
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isDeleteTransitioning = false
                }
            } else {
                onDelete?(photoToDelete)
                onDismiss()
            }
        }
    }

    // MARK: - Reset
    private func resetPosition() {
        hasTriggeredHaptic = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            offset = .zero
            isDragging = false
        }
    }

    private func resetPositionWithBounce() {
        hasTriggeredHaptic = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            offset = .zero
            isDragging = false
        }
    }

    private func resetPositionImmediate() {
        hasTriggeredHaptic = false
        offset = .zero
        isDragging = false
    }

    // MARK: - Haptic Feedback
    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func triggerConfirmHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

// MARK: - Preview
#Preview {
    @Previewable @State var deleteTrigger = 0
    DraggablePhotoView(
        photos: [],
        currentPhotoID: "",
        deleteTrigger: $deleteTrigger,
        onPhotoChange: { _, _ in },
        onDismiss: {},
        screenSize: CGSize(width: 393, height: 852)
    )
}

// MARK: - Zoom Pan Gesture
/// 放大态平移 / 全屏态下拉收拢共用的双轴手势：isZoomEnabled 为 false 时
/// 立即失败，零干扰让权给外层切图手势与 ScrollView（让权策略与
/// DirectionalHorizontalPanGesture 互补）
final class ZoomablePanGestureRecognizer: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    var isEnabledProvider: (() -> Bool)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        cancelsTouchesInView = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if !(isEnabledProvider?() ?? false) {
            state = .failed
            return
        }
        super.touchesBegan(touches, with: event)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === self else { return true }
        return isEnabledProvider?() ?? false
    }
}

@available(iOS 18.0, *)
struct ZoomPanGesture: UIGestureRecognizerRepresentable {
    var isZoomEnabled: () -> Bool
    var onChanged: ((CGPoint) -> Void)?
    var onEnded: ((CGPoint, CGPoint) -> Void)?

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIGestureRecognizer(context: Context) -> ZoomablePanGestureRecognizer {
        let recognizer = ZoomablePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        recognizer.isEnabledProvider = isZoomEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: ZoomablePanGestureRecognizer, context: Context) {
        recognizer.isEnabledProvider = isZoomEnabled
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject {
        var onChanged: ((CGPoint) -> Void)?
        var onEnded: ((CGPoint, CGPoint) -> Void)?

        init(onChanged: ((CGPoint) -> Void)?, onEnded: ((CGPoint, CGPoint) -> Void)?) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ recognizer: ZoomablePanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)
            switch recognizer.state {
            case .began, .changed:
                onChanged?(translation)
            case .ended:
                onEnded?(translation, velocity)
            case .cancelled, .failed:
                onEnded?(translation, .zero)
            default:
                break
            }
        }
    }
}

// MARK: - Single / Double Tap Gesture
/// 单击与双击共存识别：第一击启动短计时（0.25s），窗口内第二击判定双击并取消
/// 单击；窗口超时判定单击。解决 SwiftUI 原生 onTapGesture(count:1/2) 同时挂载
/// 时单击抢先于双击触发的问题。cancelsTouchesInView=false 不阻碍子视图控件。
final class SingleDoubleTapGestureRecognizer: UITapGestureRecognizer {
    var onSingle: (() -> Void)?
    var onDouble: (() -> Void)?

    private var pendingTapCount = 0
    private var singleTapTimer: Timer?
    private static let doubleTapWindow: TimeInterval = 0.25

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard state == .ended else { return }
        pendingTapCount += 1
        if pendingTapCount == 1 {
            singleTapTimer = Timer.scheduledTimer(
                withTimeInterval: Self.doubleTapWindow, repeats: false
            ) { [weak self] _ in
                guard let self else { return }
                guard self.pendingTapCount == 1 else { return }
                self.pendingTapCount = 0
                self.onSingle?()
            }
        } else {
            // 窗口内第二击：双击成立，取消待发的单击
            singleTapTimer?.invalidate()
            singleTapTimer = nil
            pendingTapCount = 0
            onDouble?()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        cancelPendingTap()
    }

    private func cancelPendingTap() {
        singleTapTimer?.invalidate()
        singleTapTimer = nil
        pendingTapCount = 0
    }
}

@available(iOS 18.0, *)
struct SingleDoubleTapGesture: UIGestureRecognizerRepresentable {
    var onSingle: (() -> Void)?
    var onDouble: (() -> Void)?

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onSingle: onSingle, onDouble: onDouble)
    }

    func makeUIGestureRecognizer(context: Context) -> SingleDoubleTapGestureRecognizer {
        let recognizer = SingleDoubleTapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        // 桥接到 coordinator 的最新闭包（update 时只刷新 coordinator，桥接保持不变）
        recognizer.onSingle = { [weak coordinator = context.coordinator] in
            coordinator?.onSingle?()
        }
        recognizer.onDouble = { [weak coordinator = context.coordinator] in
            coordinator?.onDouble?()
        }
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: SingleDoubleTapGestureRecognizer, context: Context) {
        context.coordinator.onSingle = onSingle
        context.coordinator.onDouble = onDouble
    }

    final class Coordinator: NSObject {
        var onSingle: (() -> Void)?
        var onDouble: (() -> Void)?

        init(onSingle: (() -> Void)?, onDouble: (() -> Void)?) {
            self.onSingle = onSingle
            self.onDouble = onDouble
        }

        @objc func handleTap(_ recognizer: SingleDoubleTapGestureRecognizer) {
            // 空实现：识别回调由 recognizer 子类的 touchesEnded 计时逻辑接管
        }
    }
}

// MARK: - Directional Horizontal Pan Gesture
/// 专用于垂直流式页面内的单向水平滑动手势：
/// 1. 优先判定：当手指滑动初始方向更偏向纵向（abs(y) > abs(x) 且 > 4pt）时，立即置为 .failed，
///    将触摸事件瞬时且无损地让权移交给外层父级 UIScrollView 滚动页面。
/// 2. 横向判定：当横向位移主导时正常识别，驱动卡片切换；并在拖拽期间互斥阻止外层纵向滚动抖动。
/// 3. cancelsTouchesInView = false 保留视频控制按钮（播放/暂停/静音）等子视图点击事件。
final class DirectionalHorizontalPanGestureRecognizer: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        cancelsTouchesInView = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        // 若初始触摸点直接落在屏幕最左边缘（< 22pt），立即失败让权给系统原生边缘侧滑返回
        if let touch = touches.first, touch.location(in: nil).x < 22 {
            state = .failed
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible {
            // 边缘保护：若手指在初始微移阶段落在屏幕最左边缘（< 22pt），立即失败让权
            if let touch = touches.first, touch.location(in: nil).x < 22 {
                state = .failed
                return
            }

            let translation = self.translation(in: view)
            let absX = abs(translation.x)
            let absY = abs(translation.y)
            // 纵向滑动优先退出：只要检测到纵向趋势（absY >= absX 且产生微移 > 1pt），
            // 在调用 super.touchesMoved 之前立即置为 .failed，
            // 彻底杜绝手势进入 .began，将触摸控制权零延迟让渡给外层 ScrollView
            if absY >= absX && absY > 1 {
                state = .failed
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === self else { return true }
        guard let view = self.view else { return false }

        let v = velocity(in: view)
        let t = translation(in: view)

        // 判定用户意图：必须明确是横向滑动，才允许本水平切图手势开始。
        // 1. 如果纵向速度大于等于横向速度，说明用户意在上下滚动页面，直接拒绝手势开始
        if abs(v.y) >= abs(v.x) {
            return false
        }
        // 2. 如果纵向累计位移大于等于横向累计位移，直接拒绝
        if abs(t.y) >= abs(t.x) && abs(t.y) > 0 {
            return false
        }

        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 水平滑动切图拖拽中时，互斥阻止外层垂直 ScrollView 发生纵向抖动
        if state == .began || state == .changed {
            if otherGestureRecognizer is UIPanGestureRecognizer {
                return false
            }
        }
        return true
    }
}

@available(iOS 18.0, *)
struct DirectionalHorizontalPanGesture: UIGestureRecognizerRepresentable {
    var onChanged: ((CGPoint) -> Void)?
    var onEnded: ((CGPoint, CGPoint) -> Void)?

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIGestureRecognizer(context: Context) -> DirectionalHorizontalPanGestureRecognizer {
        DirectionalHorizontalPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
    }

    func updateUIGestureRecognizer(_ recognizer: DirectionalHorizontalPanGestureRecognizer, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject {
        var onChanged: ((CGPoint) -> Void)?
        var onEnded: ((CGPoint, CGPoint) -> Void)?

        init(onChanged: ((CGPoint) -> Void)?, onEnded: ((CGPoint, CGPoint) -> Void)?) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ recognizer: DirectionalHorizontalPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)
            switch recognizer.state {
            case .began, .changed:
                onChanged?(translation)
            case .ended:
                onEnded?(translation, velocity)
            case .cancelled, .failed:
                onEnded?(translation, .zero)
            default:
                break
            }
        }
    }
}

