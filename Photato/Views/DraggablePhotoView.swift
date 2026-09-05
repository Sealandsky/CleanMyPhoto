
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

    /// 卡片版式：fullScreen = 独立全屏页（默认，上下各留 120pt 给页面操作栏）；
    /// embeddedSection = 作为详情页垂直版式中的预览区嵌入，上下不留白让大图占满区块
    enum CardPresentation {
        case fullScreen
        case embeddedSection
    }
    var cardPresentation: CardPresentation = .fullScreen

    private var effectiveCardTopPadding: CGFloat {
        cardPresentation == .embeddedSection ? 0 : cardTopPadding
    }
    private var effectiveCardBottomPadding: CGFloat {
        cardPresentation == .embeddedSection ? 0 : cardBottomPadding
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
        deleteTrigger: Binding<Int>,
        onPhotoChange: @escaping (String, Int) -> Void,
        onDelete: ((PhotoAsset) -> Void)? = nil,
        onBlockedDelete: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void,
        screenSize: CGSize,
        cardPresentation: CardPresentation = .fullScreen,
        isFavorite: ((PhotoAsset) -> Bool)? = nil
    ) {
        self.photos = photos
        self.currentPhotoID = currentPhotoID
        self._deleteTrigger = deleteTrigger
        self.onPhotoChange = onPhotoChange
        self.onDelete = onDelete
        self.onBlockedDelete = onBlockedDelete
        self.onDismiss = onDismiss
        self.screenSize = screenSize
        self.cardPresentation = cardPresentation
        self.isFavorite = isFavorite
        let idx = photos.firstIndex(where: { $0.id == currentPhotoID }) ?? 0
        _localIndex = State(initialValue: idx)
    }

    var body: some View {
        gestureContainer
    }

    /// 手势挂载：全屏版式独占拖动（上下滑删除/退出，左右滑切换）；
    /// 垂直流式嵌入版式使用高精度单向水平手势 DirectionalHorizontalPanGesture，
    /// 纵向滑动瞬间让权给外层 ScrollView，水平滑动丝滑切换素材
    @ViewBuilder
    private var gestureContainer: some View {
        if cardPresentation == .embeddedSection {
            cardStack.gesture(
                DirectionalHorizontalPanGesture(
                    onChanged: { translation in
                        handleHorizontalPanChanged(translation: translation)
                    },
                    onEnded: { translation, velocity in
                        handleHorizontalPanEnded(translation: translation, velocity: velocity)
                    }
                )
            )
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
            ZStack {
                backgroundLayer
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())

                // 仅在手指拖拽或切图动画中渲染相邻卡片；静止闲置时只有当前照片存在，彻底杜绝矮宽图背后透出相邻图片
                if (isDragging || isNavigating || offset != .zero), let prev = previousPhoto, !isDeleteTransitioning {
                    mediaCardLayer(prev, isCurrent: false, containerSize: geometry.size)
                        .offset(x: -geometry.size.width - photoSpacing + offset.width)
                        .zIndex(0)
                }

                // 当前照片卡片
                mediaCardLayer(currentPhoto, isCurrent: true, containerSize: geometry.size)
                    .offset(x: offset.width, y: offset.height)
                    .zIndex(1)

                // 仅在手指拖拽或切图动画中渲染相邻卡片
                if (isDragging || isNavigating || offset != .zero), let next = nextPhoto {
                    mediaCardLayer(next, isCurrent: false, containerSize: geometry.size)
                        .offset(x: geometry.size.width + photoSpacing + offset.width)
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
            .clipped()
        }
        .onChange(of: currentPhotoID) { _, newID in
            guard !isDeleteTransitioning, !isNavigating else { return }
            if let idx = photos.firstIndex(where: { $0.id == newID }) {
                localIndex = idx
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

    /// 区块底色：全屏版式统一使用系统分组背景底色（与设置页一致）；
    /// 垂直流式嵌入版式不绘制底色，透出详情页统一页面底色（systemGroupedBackground）
    @ViewBuilder
    private var backgroundLayer: some View {
        if cardPresentation == .embeddedSection {
            Color.clear
        } else {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
        }
    }

    // MARK: - Card Size Helper
    private func cardSize(for photoAsset: PhotoAsset, in available: CGSize) -> CGSize {
        guard available.width > 0, available.height > 0 else { return .zero }
        let ratio = photoAsset.pixelAspectRatio
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

    // MARK: - Media Card Layer（当前卡片与相邻卡片共用统一视图骨架，杜绝切图瞬间视图替换闪烁与卡顿）
    @ViewBuilder
    private func mediaCardLayer(_ photoAsset: PhotoAsset, isCurrent: Bool, containerSize: CGSize) -> some View {
        let available = CGSize(
            width: max(0, containerSize.width - cardPadding * 2),
            height: max(0, containerSize.height - effectiveCardTopPadding - effectiveCardBottomPadding)
        )
        let size = cardSize(for: photoAsset, in: available)

        switch photoAsset.mediaType {
        case .video:
            ZStack {
                AssetImage(asset: photoAsset.asset, targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .fit, highQuality: true)
                    .frame(width: size.width, height: size.height)

                if isCurrent {
                    VideoPlayerView(asset: photoAsset.asset, isDragging: $isDragging)
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(cardShadowOpacity), radius: cardShadowRadius, x: 0, y: 4)
            .frame(width: containerSize.width, height: containerSize.height)
            .id(photoAsset.id)

        case .livePhoto:
            ZStack {
                AssetImage(asset: photoAsset.asset, targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .fit, highQuality: true)
                    .frame(width: size.width, height: size.height)

                if isCurrent {
                    LivePhotoPlayerView(asset: photoAsset.asset)
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(cardShadowOpacity), radius: cardShadowRadius, x: 0, y: 4)
            .frame(width: containerSize.width, height: containerSize.height)
            .id(photoAsset.id)

        default:
            AssetImage(asset: photoAsset.asset, targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .fit, highQuality: true)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(cardShadowOpacity), radius: cardShadowRadius, x: 0, y: 4)
                .frame(width: containerSize.width, height: containerSize.height)
                .id(photoAsset.id)
        }
    }
    // MARK: - Gesture Handlers
    @State private var showDeleteIndicator = false

    /// 水平单向手势位移回调：驱动卡片横向视差滑动
    private func handleHorizontalPanChanged(translation: CGPoint) {
        if isNavigating { return }
        isDragging = true
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
            offset = CGSize(width: translation.x, height: 0)
        }
    }

    /// 水平单向手势结束回调：判定滑动距离与速度决定是否切图
    private func handleHorizontalPanEnded(translation: CGPoint, velocity: CGPoint) {
        if isNavigating { return }
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

