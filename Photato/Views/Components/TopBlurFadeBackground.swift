import SwiftUI

// MARK: - Top Blur Fade Background
/// 顶部标题栏的柔和淡出模糊背景。
///
/// 使用系统材质（ultraThinMaterial）提供原生模糊，再以垂直渐变遮罩控制
/// 可见度：顶部完全不透明（模糊最强），向下逐步衰减至透明——
/// 替代导航栏底部生硬的分界线，实现向下柔和淡出的过渡。
///
/// 用法：挂在页面内容顶部（background），同时隐藏系统导航栏背景：
/// ```swift
/// content
///     .toolbarBackground(.hidden, for: .navigationBar)
///     .background(alignment: .top) { TopBlurFadeBackground(height: 200) }
/// ```
struct TopBlurFadeBackground: View {
    /// 模糊背景的总高度（含状态栏与导航栏区域，向下渐隐）
    var height: CGFloat = 200
    /// 完全不透明区段的占比（0~1），其余部分线性衰减到透明
    var solidFraction: Double = 0.55

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            // 垂直渐变遮罩：材质可见度自上而下衰减，实现模糊的柔和淡出
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: solidFraction),
                        .init(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            // 上探到状态栏之后，模糊覆盖状态栏与导航栏完整区域
            .ignoresSafeArea(edges: .top)
    }
}

#Preview("Top Blur Fade") {
    ZStack(alignment: .top) {
        Color.black.ignoresSafeArea()
        TopBlurFadeBackground(height: 200)
        Text("Content Behind")
            .foregroundColor(.white)
    }
}
