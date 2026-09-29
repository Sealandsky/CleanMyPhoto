import SwiftUI

/// 二级页面与详情页通用的滚动动态毛玻璃导航栏修饰器：
/// 1. 隐藏系统导航栏自带背景，由本修饰器接管渲染；
/// 2. 静止置顶状态（scrollOffsetY == 0）：完全透明，0 遮挡内容，页面底色与大图/卡片 100% 纯净呈现；
/// 3. 随手势连续过渡（0 ~ 20pt）：透明度随上滑位移平滑线性渐入（opacity: 0.0 -> 1.0）；
/// 4. 材质与色调：采用系统原生 .ultraThinMaterial + .colorMultiply(Color.pageBackground.opacity(0.35)) 色调校准；
/// 5. 覆盖范围：精确覆盖状态栏与 44pt 导航栏区域，无任何向下延伸遮挡；
/// 6. 低版本与无障碍兼容：开启降低透明度或低版本时回退纯色 Color.pageBackground (#F3F3F3) 实体底色。
public struct DynamicSecondaryNavBarModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var internalScrollOffsetY: CGFloat = 0
    private var externalScrollOffsetY: CGFloat?
    private var opacityMultiplier: CGFloat

    private var effectiveScrollOffsetY: CGFloat {
        externalScrollOffsetY ?? internalScrollOffsetY
    }

    private var scrollProgress: CGFloat {
        let progress = min(1.0, max(0.0, effectiveScrollOffsetY / 20.0))
        return progress * opacityMultiplier
    }

    public init(scrollOffsetY: CGFloat? = nil, opacityMultiplier: CGFloat = 1.0) {
        self.externalScrollOffsetY = scrollOffsetY
        self.opacityMultiplier = opacityMultiplier
    }

    public func body(content: Content) -> some View {
        Group {
            if externalScrollOffsetY != nil {
                content
            } else {
                content
                    .onScrollGeometryChange(for: CGFloat.self) { geo in
                        geo.contentOffset.y + geo.contentInsets.top
                    } action: { _, newOffset in
                        internalScrollOffsetY = max(0, newOffset)
                    }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background {
                    navBarDynamicBackground
                }
        }
    }

    @ViewBuilder
    private var navBarDynamicBackground: some View {
        if #available(iOS 15.0, *), !reduceTransparency {
            Rectangle()
                .fill(.ultraThinMaterial)
                .colorMultiply(Color.pageBackground.opacity(0.35))
                .opacity(scrollProgress)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        } else {
            Color.pageBackground
                .opacity(scrollProgress)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// 为二级页面与详情页应用滚动动态吸顶毛玻璃导航栏
    /// - Parameters:
    ///   - scrollOffsetY: 可选显式传入由外部跟踪的滚动偏移量（如 nil 则内部自动监听）
    ///   - opacityMultiplier: 可选透明度倍率（如全屏沉浸展开时随进度淡出）
    public func dynamicSecondaryNavigationBar(
        scrollOffsetY: CGFloat? = nil,
        opacityMultiplier: CGFloat = 1.0
    ) -> some View {
        self.modifier(DynamicSecondaryNavBarModifier(
            scrollOffsetY: scrollOffsetY,
            opacityMultiplier: opacityMultiplier
        ))
    }
}
