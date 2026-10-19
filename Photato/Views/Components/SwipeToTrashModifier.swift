import SwiftUI
import Photos
import UIKit

// MARK: - Card Swipe Pan Gesture Recognizer
/// 卡片左右滑动删除手势识别器：
/// 1. 深度对齐 iOS Safari 标签页横滑手势逻辑；
/// 2. 纵向滑动意图（纵向位移/速度占优）优先退出，零延迟让权给外层垂直 ScrollView；
/// 3. 横向手势确立后（began/changed），互斥阻止外层 ScrollView 纵向拖动，消除斜滑对冲抖动；
/// 4. 屏幕最左侧（< 22pt）边缘手势让权给系统原生边缘侧滑返回；
/// 5. 未触发横滑时放行轻点事件，保留原有的点击查看大图逻辑。
final class CardSwipePanGestureRecognizer: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    var isEnabledProvider: (() -> Bool)?
    private var initialTouchPoint: CGPoint? = nil

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        cancelsTouchesInView = false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === self else { return true }
        if let isEnabled = isEnabledProvider, !isEnabled() {
            return false
        }
        return true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let isEnabled = isEnabledProvider, !isEnabled() {
            state = .failed
            return
        }
        if let touch = touches.first {
            // 边缘保护：触摸点直接落在屏幕最左边缘（< 22pt），让权给导航控制器原生边缘侧滑返回
            if touch.location(in: nil).x < 22 {
                state = .failed
                return
            }
            if let view = self.view {
                initialTouchPoint = touch.location(in: view)
            }
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible {
            if let isEnabled = isEnabledProvider, !isEnabled() {
                state = .failed
                return
            }

            if let touch = touches.first, touch.location(in: nil).x < 22 {
                state = .failed
                return
            }

            let translation = self.translation(in: view)
            let absX = abs(translation.x)
            let absY = abs(translation.y)

            // 纵向滑动优先让权：当检测到纵向趋势（absY >= absX 且产生微移 > 5pt）时，
            // 立即置为 .failed，将触摸控制权零延迟让渡给外层 ScrollView，保证上下滚动 120Hz 丝滑
            if absY >= absX && absY > 5 {
                state = .failed
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        initialTouchPoint = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        initialTouchPoint = nil
    }

    override func reset() {
        super.reset()
        initialTouchPoint = nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === self else { return true }
        if let isEnabled = isEnabledProvider, !isEnabled() {
            return false
        }
        guard let view = self.view else { return false }

        let v = velocity(in: view)
        let t = translation(in: view)

        // 必须明确判定为横向滑动意图才允许手势开始：
        // 1. 纵向速度大于等于横向速度，说明用户意在上下滚动列表，直接拒绝
        if abs(v.y) >= abs(v.x) {
            return false
        }
        // 2. 纵向累计位移大于等于横向累计位移，直接拒绝
        if abs(t.y) >= abs(t.x) && abs(t.y) > 0 {
            return false
        }

        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 卡片横滑手势拖拽中时，互斥阻止外层垂直 ScrollView 发生纵向滚动
        if state == .began || state == .changed {
            if otherGestureRecognizer is UIPanGestureRecognizer {
                return false
            }
        }
        return true
    }
}

// MARK: - Card Swipe Pan Gesture (UIGestureRecognizerRepresentable)
@available(iOS 18.0, *)
struct CardSwipePanGesture: UIGestureRecognizerRepresentable {
    var isEnabled: (() -> Bool)? = nil
    var onChanged: ((CGPoint, CGPoint) -> Void)?
    var onEnded: ((CGPoint, CGPoint) -> Void)?

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIGestureRecognizer(context: Context) -> CardSwipePanGestureRecognizer {
        let recognizer = CardSwipePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        recognizer.isEnabledProvider = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: CardSwipePanGestureRecognizer, context: Context) {
        recognizer.isEnabledProvider = isEnabled
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject {
        var onChanged: ((CGPoint, CGPoint) -> Void)?
        var onEnded: ((CGPoint, CGPoint) -> Void)?

        init(onChanged: ((CGPoint, CGPoint) -> Void)?, onEnded: ((CGPoint, CGPoint) -> Void)?) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ recognizer: CardSwipePanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)
            switch recognizer.state {
            case .began, .changed:
                onChanged?(translation, velocity)
            case .ended, .cancelled:
                onEnded?(translation, velocity)
            default:
                break
            }
        }
    }
}

// MARK: - Swipe To Trash Modifier
/// 类似 Safari 移动端标签页左右滑出删除的 ViewModifier
struct SwipeToTrashModifier: ViewModifier {
    let photo: PhotoAsset
    var isEnabled: Bool = true
    var isFavorite: Bool = false
    var onTrash: (PhotoAsset) -> Void
    var onBlocked: (() -> Void)? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isDismissing: Bool = false
    @State private var cardOpacity: CGFloat = 1.0
    @State private var hasTriggeredArmedHaptic: Bool = false

    /// 触发删除的位移阈值（约 85pt，接近双列网格卡片宽度的 45%）
    private static let triggerDistance: CGFloat = 85
    /// 触发轻甩删除的速度阈值（550 pt/s）
    private static let flickVelocity: CGFloat = 550

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .rotationEffect(.degrees(Double(dragOffset / 180.0) * 3.5))
            .opacity(cardOpacity)
            .scaleEffect(isDragging ? 0.98 : 1.0)
            .zIndex(isDragging || isDismissing ? 2 : 0)
            .allowsHitTesting(!isDismissing && (!isDragging || abs(dragOffset) < 5))
            .gesture(
                CardSwipePanGesture(
                    isEnabled: {
                        isEnabled && !isDismissing
                    },
                    onChanged: { translation, _ in
                        handlePanChanged(translation: translation)
                    },
                    onEnded: { translation, velocity in
                        handlePanEnded(translation: translation, velocity: velocity)
                    }
                )
            )
    }

    private func handlePanChanged(translation: CGPoint) {
        isDragging = true

        if isFavorite {
            // 收藏照片受保护：提供橡皮筋非线性阻尼，最大位移限制在 45pt
            let damped = translation.x * 0.22
            dragOffset = max(-45, min(45, damped))
            return
        }

        dragOffset = translation.x
        // 透明度平滑衰减：向两侧滑出时渐隐，最低保留 0.35
        let progress = min(1.0, abs(translation.x) / (ScreenSizeHelper.screenSize.width * 0.6))
        cardOpacity = max(0.35, 1.0 - progress * 0.65)

        // 越过阈值即刻触发段落感 Armed 触觉反馈
        if abs(translation.x) >= Self.triggerDistance {
            if !hasTriggeredArmedHaptic {
                hasTriggeredArmedHaptic = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } else if abs(translation.x) < Self.triggerDistance - 15 {
            hasTriggeredArmedHaptic = false
        }
    }

    private func handlePanEnded(translation: CGPoint, velocity: CGPoint) {
        isDragging = false
        hasTriggeredArmedHaptic = false

        if isFavorite {
            // 收藏照片弹簧归位并提示受保护
            if abs(dragOffset) > 15 {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                onBlocked?()
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                dragOffset = 0
            }
            return
        }

        // 判定是否达到删除条件：位移超阈值 或 同向轻甩速度超阈值且有一定微移
        let isOverDistance = abs(translation.x) >= Self.triggerDistance
        let isFlick = abs(velocity.x) >= Self.flickVelocity && abs(translation.x) > 20 && (velocity.x * translation.x > 0)

        if isOverDistance || isFlick {
            isDismissing = true
            // 顺应滑行方向加速飞出屏幕
            let direction: CGFloat = (translation.x > 0 || (abs(translation.x) <= 20 && velocity.x > 0)) ? 1 : -1
            let flyOutTarget = direction * (ScreenSizeHelper.screenSize.width + 120)

            withAnimation(.easeOut(duration: 0.22)) {
                dragOffset = flyOutTarget
                cardOpacity = 0
            }

            // 飞出后派发删除，驱动网格流体补位
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    onTrash(photo)
                }
            }
        } else {
            // 未越过阈值：弹性平滑回弹归位
            withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                dragOffset = 0
                cardOpacity = 1.0
            }
        }
    }
}

// MARK: - View Extension
extension View {
    /// 为照片卡片提供类似 Safari 标签页的左右滑出移入回收站交互
    func swipeToTrash(
        photo: PhotoAsset,
        isEnabled: Bool = true,
        isFavorite: Bool = false,
        onTrash: @escaping (PhotoAsset) -> Void,
        onBlocked: (() -> Void)? = nil
    ) -> some View {
        modifier(
            SwipeToTrashModifier(
                photo: photo,
                isEnabled: isEnabled,
                isFavorite: isFavorite,
                onTrash: onTrash,
                onBlocked: onBlocked
            )
        )
    }
}
