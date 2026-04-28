//
//  ScreenSizeHelper.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/10.
//

import UIKit

/// 屏幕尺寸辅助工具
struct ScreenSizeHelper {

    /// 获取当前活跃的 UIScreen
    private static var activeScreen: UIScreen {
        if #available(iOS 26, *) {
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return windowScene?.screen ?? UIScreen.main
        } else {
            return UIScreen.main
        }
    }

    /// 获取屏幕逻辑尺寸
    static var screenSize: CGSize {
        activeScreen.bounds.size
    }

    /// 获取屏幕缩放比例
    static var screenScale: CGFloat {
        activeScreen.scale
    }

    /// 获取屏幕物理像素尺寸（考虑屏幕缩放因素）
    /// - Returns: 屏幕的物理像素尺寸（例如 iPhone 14 Pro: 1179×2556）
    static var screenPhysicalSize: CGSize {
        let size = screenSize
        let scale = screenScale
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
