import SwiftUI

extension ShapeStyle where Self == LinearGradient {
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0, green: 0.52, blue: 1.0), Color(red: 0, green: 0.72, blue: 1.0)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// 整理页天空渐变背景（对标现代健康数据仪表盘：顶部天蓝向底部温和白过渡）
    static var organizeSkyGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 62/255, green: 141/255, blue: 234/255), location: 0.0),    // #3E8DEA 天空蓝
                .init(color: Color(red: 89/255, green: 158/255, blue: 236/255), location: 0.14),   // #599EEC
                .init(color: Color(red: 125/255, green: 180/255, blue: 242/255), location: 0.28),  // #7DB4F2
                .init(color: Color(red: 175/255, green: 210/255, blue: 248/255), location: 0.44),  // #AFD2F8
                .init(color: Color(red: 220/255, green: 235/255, blue: 252/255), location: 0.58),  // #DCEBFC 冰蓝
                .init(color: Color(red: 246/255, green: 248/255, blue: 252/255), location: 0.74),  // #F6F8FC
                .init(color: Color.pageBackground, location: 0.90),
                .init(color: Color.pageBackground, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// 整理页专用全屏天空渐变背景组件
struct OrganizeSkyBackgroundView: View {
    var body: some View {
        LinearGradient.organizeSkyGradient
            .ignoresSafeArea()
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
