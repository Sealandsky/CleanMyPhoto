import SwiftUI
import UIKit

// MARK: - Zoom Interactive Dismiss Configurator
/// 控制 iOS 18+ NavigationStack 原生缩放转场（navigationTransition.zoom）交互式返回手势的精细配置器。
///
/// 核心交互策略：
/// 1. 屏幕边缘侧滑返回（Screen Edge Pop）：永远放行！
///    无论处于全屏大图态还是卡片态，无论滚动到最顶部还是相似图片底部，
///    只要是从屏幕左边缘（< 50pt）向右侧滑，一律 100% 允许系统原生侧滑交互式返回。
/// 2. 捏合缩放退出手势（Transform 手势识别器）：全程坚决禁用！
///    用户在全屏模式下的双指捏合仅用于缩小回详情页卡片；在详情页卡片下的双指捏合仅作为弹性阻尼回弹，杜绝误退回列表页。
/// 3. 下拉退出手势（SwipeDown 下拉识别器）：
///    - 全屏大图态（isFullScreen = true）：拦截系统转场下拉，将纵向下拖手势归大图状态机平滑收拢回卡片；
///    - 相似图片浏览态（ScrollView 已向下滚动）：拦截系统转场下拉，将手势完全归属于 ScrollView 用于向上回滚内容；
///    - 顶栏状态（ScrollView 位于最顶部）：完全放行系统原生带指尖跟随、缩放动效与物理弹簧回弹的交互式转场下拉退出！
struct ZoomInteractiveDismissConfigurator: UIViewControllerRepresentable {
    var isFullScreen: Bool
    var scrollOffsetY: CGFloat

    func makeUIViewController(context: Context) -> ConfiguratorViewController {
        ConfiguratorViewController(isFullScreen: isFullScreen, scrollOffsetY: scrollOffsetY)
    }

    func updateUIViewController(_ uiViewController: ConfiguratorViewController, context: Context) {
        uiViewController.isFullScreen = isFullScreen
        uiViewController.scrollOffsetY = scrollOffsetY
        uiViewController.applyConfiguration()
    }

    final class ConfiguratorViewController: UIViewController {
        var isFullScreen: Bool
        var scrollOffsetY: CGFloat

        init(isFullScreen: Bool, scrollOffsetY: CGFloat) {
            self.isFullScreen = isFullScreen
            self.scrollOffsetY = scrollOffsetY
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isHidden = true
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyConfiguration()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyConfiguration()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.applyConfiguration()
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // 离开详情页时恢复手势默认启用状态，避免影响其他页面
            setTransitionGesturesEnabled(true)
        }

        func applyConfiguration() {
            guard #available(iOS 18.0, *) else { return }

            // 1. 向上查找持有 preferredTransition 的宿主 HostingController
            var current: UIViewController? = self
            while let vc = current {
                if let transition = vc.preferredTransition {
                    configureTransition(transition)
                }
                configureGestures(on: vc)
                current = vc.parent
            }

            // 2. 检查 navigationController?.topViewController
            if let topVC = navigationController?.topViewController {
                if let transition = topVC.preferredTransition {
                    configureTransition(transition)
                }
                configureGestures(on: topVC)
            }
        }

        private func configureTransition(_ transition: UIViewController.Transition) {
            guard #available(iOS 18.0, *) else { return }
            let transitionObj = transition as AnyObject
            let optionsSelector = NSSelectorFromString("options")
            guard transitionObj.responds(to: optionsSelector) else { return }
            guard let options = transitionObj.value(forKey: "options") as? UIViewController.Transition.ZoomOptions else {
                return
            }
            options.interactiveDismissShouldBegin = { [weak self] context in
                guard let self = self else { return true }
                return self.shouldBeginInteractiveDismiss(context: context)
            }
        }

        private func shouldBeginInteractiveDismiss(context: UIViewController.Transition.ZoomOptions.InteractionContext) -> Bool {
            // 1. 屏幕边缘侧滑返回（Screen Edge Pop）：永远放行！
            // 无论是卡片还是全屏，无论是在顶部还是底部，只要是从屏幕左侧边缘（< 50pt）向右滑，完全放行！
            let isFromLeftEdge = context.location.x < 50 || (context.velocity.dx > 100 && abs(context.velocity.dx) > abs(context.velocity.dy))
            if isFromLeftEdge {
                return true
            }

            // 2. 全屏大图展开态（isFullScreen = true）：
            // 下拉手势归大图状态机处理（单指下拉收拢回卡片，单指放大平移），绝不允许直接退回列表页！
            if isFullScreen {
                return false
            }

            // 3. 详情页卡片态（isFullScreen = false）：
            // 优先从 UIKit 视图层级实时获取真实 UIScrollView 的 contentOffset，避免 SwiftUI 状态同步延迟
            let isAtTop: Bool
            if let sv = findVerticalScrollView() {
                isAtTop = (sv.contentOffset.y + sv.adjustedContentInset.top) <= 2
            } else {
                isAtTop = scrollOffsetY <= 2
            }

            // 如果用户正在向上滑浏览下方的相似照片（ScrollView 已向下滚动），
            // 此时向下滑动手势必须用于向上回滚内容，严禁触发退出！
            if !isAtTop {
                return false
            }

            // 4. 处于最顶栏时向下拖拽：放行系统原生交互式 Zoom 转场返回！
            return true
        }

        private func findVerticalScrollView() -> UIScrollView? {
            var rootVC: UIViewController? = self
            while let parent = rootVC?.parent {
                rootVC = parent
            }
            guard let targetView = rootVC?.view ?? parent?.view ?? view.superview else { return nil }
            return findVerticalScrollView(in: targetView)
        }

        private func findVerticalScrollView(in view: UIView) -> UIScrollView? {
            if let sv = view as? UIScrollView, sv.frame.height > 200 {
                return sv
            }
            for subview in view.subviews {
                if let sv = findVerticalScrollView(in: subview) {
                    return sv
                }
            }
            return nil
        }

        private func configureGestures(on vc: UIViewController) {
            guard let recognizers = vc.view.gestureRecognizers else { return }
            for recognizer in recognizers {
                let className = NSStringFromClass(type(of: recognizer))
                // 转场双指捏合手势（Transform 识别器）：
                // 在进入详情页后坚决禁用！
                // 用户在详情页或全屏下的任何双指捏合仅作为图片缩放/展开收拢交互，绝对禁止退回列表页。
                // 若未来系统版本手势类名发生变动，识别器过滤安全跳过并回退至默认手势，绝不阻塞触摸或闪退。
                if className.contains("Transform") {
                    if recognizer.isEnabled {
                        recognizer.isEnabled = false
                    }
                }
                // 注意：SwipeDown 下拉识别器保持 isEnabled = true！
                // 它的触发由上面的 options.interactiveDismissShouldBegin 动态接管：
                // 顶栏时放行原生交互转场退出，向下滚动浏览相似照片时动态拦截让权给 ScrollView。
                else if className.contains("SwipeDown") {
                    if !recognizer.isEnabled {
                        recognizer.isEnabled = true
                    }
                }
            }
        }

        private func setTransitionGesturesEnabled(_ enabled: Bool) {
            var current: UIViewController? = self
            while let vc = current {
                if let recognizers = vc.view.gestureRecognizers {
                    for recognizer in recognizers {
                        let className = NSStringFromClass(type(of: recognizer))
                        if className.contains("Transform") || className.contains("SwipeDown") {
                            recognizer.isEnabled = enabled
                        }
                    }
                }
                current = vc.parent
            }
            if let topVC = navigationController?.topViewController,
               let recognizers = topVC.view.gestureRecognizers {
                for recognizer in recognizers {
                    let className = NSStringFromClass(type(of: recognizer))
                    if className.contains("Transform") || className.contains("SwipeDown") {
                        recognizer.isEnabled = enabled
                    }
                }
            }
        }
    }
}
