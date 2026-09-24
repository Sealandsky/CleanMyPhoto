import SwiftUI

extension ShapeStyle where Self == LinearGradient {
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0, green: 0.52, blue: 1.0), Color(red: 0, green: 0.72, blue: 1.0)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

extension Color {
    /// 统一页面底色与标题栏底色 #F3F3F3
    static let pageBackground = Color(.sRGB, red: 243/255, green: 243/255, blue: 243/255)

    /// 统一卡片底色 #E9EAEB（相簿堆叠卡、清理功能入口卡、设置页会员卡共用）
    static let cardBackground = Color(.sRGB, red: 233/255, green: 234/255, blue: 235/255)
}

extension UIColor {
    /// 统一页面底色与标题栏底色 #F3F3F3
    static let pageBackground = UIColor(red: 243/255, green: 243/255, blue: 243/255, alpha: 1.0)
}

extension Font {
    /// 对齐 Apple HIG Title 1 / UIFont.TextStyle.title1 (28pt)
    public static var title1: Font {
        .system(.title, design: .rounded).weight(.bold)
    }
}
