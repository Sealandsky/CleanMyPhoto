import UIKit

/// 屏幕尺寸辅助工具
struct ScreenSizeHelper {

    /// 获取当前活跃的 UIScreen
    @available(iOS, deprecated: 26, message: "Use view environment traits or GeometryReader instead")
    private static var activeScreen: UIScreen {
        if #available(iOS 26, *) {
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return windowScene?.screen ?? UIScreen.main
        }
        return UIScreen.main
    }

    /// 获取屏幕逻辑尺寸
    static var screenSize: CGSize {
        activeScreen.bounds.size
    }

    /// 获取屏幕缩放比例
    static var screenScale: CGFloat {
        activeScreen.scale
    }

    /// 获取屏幕物理像素尺寸（例如 iPhone 14 Pro: 1179×2556）
    static var screenPhysicalSize: CGSize {
        let size = screenSize
        let scale = screenScale
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// 适合详情/重温页大图展示的适度像素尺寸（宽度对齐屏幕宽度物理像素，高度约占屏幕 60% 物理像素，避免请求过大尺寸导致解码耗时与内存飙升）
    static var cardPhysicalSize: CGSize {
        let size = screenSize
        let scale = screenScale
        return CGSize(width: size.width * scale, height: size.height * 0.6 * scale)
    }
}
