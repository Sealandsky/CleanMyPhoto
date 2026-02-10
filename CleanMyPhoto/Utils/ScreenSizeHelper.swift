//
//  ScreenSizeHelper.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/10.
//

import UIKit

/// 屏幕尺寸辅助工具
struct ScreenSizeHelper {

    /// 获取屏幕物理像素尺寸（考虑屏幕缩放因素）
    /// - Returns: 屏幕的物理像素尺寸（例如 iPhone 14 Pro: 1179×2556）
    static var screenPhysicalSize: CGSize {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }
}
