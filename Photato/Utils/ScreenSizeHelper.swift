import UIKit

/// 屏幕尺寸辅助工具
struct ScreenSizeHelper {

    /// 获取当前活跃的 UIWindowScene
    private static var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
    }

    /// 获取主视窗/活跃视窗
    private static var activeKeyWindow: UIWindow? {
        if let scene = activeWindowScene {
            if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            return scene.windows.first
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// 获取屏幕/窗口逻辑尺寸（在 iPhone Duo 等多屏/双屏设备上自适应当前活跃窗口尺寸）
    static var screenSize: CGSize {
        if let window = activeKeyWindow {
            let size = window.bounds.size
            if size.width > 0 && size.height > 0 {
                return size
            }
        }
        if let scene = activeWindowScene {
            let size = scene.coordinateSpace.bounds.size
            if size.width > 0 && size.height > 0 {
                return size
            }
        }
        return CGSize(width: 393, height: 852)
    }

    /// 获取屏幕/窗口缩放比例
    static var screenScale: CGFloat {
        if let window = activeKeyWindow {
            let scale = window.traitCollection.displayScale
            if scale > 0 {
                return scale
            }
        }
        if let scene = activeWindowScene {
            let scale = scene.traitCollection.displayScale
            if scale > 0 {
                return scale
            }
        }
        return 3.0
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

    /// 重温/详情卡片直接提取的 600x600 缩略图尺寸，单次直出无需二次请求
    static let cardThumbnailSize = CGSize(width: 600, height: 600)
}
