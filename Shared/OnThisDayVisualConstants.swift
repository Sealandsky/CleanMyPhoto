import SwiftUI

// MARK: - On This Day Visual Constants
/// 「往年今日」卡片的共享视觉常量。主 App 与 Widget 都引用此表，保证视觉一致。
/// 数值与原 OnThisDaySectionView / OnThisDayCardView 中的硬编码完全一致。
enum OnThisDayVisualConstants {
    // 横幅外框
    static let bannerCornerRadius: CGFloat = 22
    // 单张照片卡
    static let cardCornerRadius: CGFloat = 20
    static let cardImageCornerRadius: CGFloat = 18
    static let cardBorderWidth: CGFloat = 2
    static let cardShadowRadius: CGFloat = 6
    static let cardShadowY: CGFloat = 3

    /// 暖色横幅渐变（与主 App bannerBackground 完全一致）
    /// - dark: #32271D → #1C1C1E
    /// - light: #EAC799 → #E5E5E3
    static func bannerGradient(isDark: Bool) -> LinearGradient {
        if isDark {
            return LinearGradient(
                colors: [
                    Color(red: 50 / 255.0, green: 39 / 255.0, blue: 29 / 255.0),
                    Color(red: 28 / 255.0, green: 28 / 255.0, blue: 30 / 255.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 234 / 255.0, green: 199 / 255.0, blue: 153 / 255.0),
                    Color(red: 229 / 255.0, green: 229 / 255.0, blue: 227 / 255.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// 中央年份文字颜色
    static func primaryText(isDark: Bool) -> Color {
        isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    /// 中央张数文字颜色
    static func secondaryText(isDark: Bool) -> Color {
        isDark
            ? Color(red: 0.65, green: 0.65, blue: 0.67)
            : Color(red: 0.48, green: 0.48, blue: 0.50)
    }
}
