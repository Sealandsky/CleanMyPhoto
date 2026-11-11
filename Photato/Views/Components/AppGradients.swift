import SwiftUI

extension ShapeStyle where Self == LinearGradient {
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0, green: 0x70 / 255.0, blue: 0xE0 / 255.0), Color(red: 0, green: 0.72, blue: 1.0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// 说明：pageBackground / cardBackground 由 Xcode 从 Assets 的 PageBackground / CardBackground
// 颜色集自动生成的符号（Color.pageBackground 等）提供，无需手写扩展。

extension Font {
    /// 对齐 Apple HIG Title 1 / UIFont.TextStyle.title1 (28pt)
    public static var title1: Font {
        .system(.title, design: .rounded).weight(.bold)
    }
}
