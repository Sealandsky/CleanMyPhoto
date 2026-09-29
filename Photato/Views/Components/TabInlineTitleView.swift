import SwiftUI

/// Tab 首页通用左侧大标题视图与修饰器：
/// 在 inline 吸顶模式下，于左侧呈现原生 .largeTitle 粗体圆角大标题，
/// 右侧操作按钮采用系统 Liquid Glass 效果，背景采用向下柔和淡出的渐变毛玻璃。
struct TabInlineTitleView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.largeTitle, design: .rounded).weight(.bold))
            .foregroundColor(.primary)
    }
}

/// 顶部吸顶栏操作按钮通用 Liquid Glass 质感修饰器：
/// iOS 26+ 使用系统原生 glassEffect 材质（包含光照折射与交互式高光）；
/// iOS 18 回退系统 ultraThinMaterial 毛玻璃胶囊底。
public struct HeaderLiquidGlassModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension View {
    /// 为顶部栏按钮添加系统 Liquid Glass 交互胶囊效果
    public func headerLiquidGlass() -> some View {
        self.modifier(HeaderLiquidGlassModifier())
    }
}

struct TabInlineHeaderModifier<Trailing: View>: ViewModifier {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var scrollOffsetY: CGFloat = 0

    /// 随滚动位移（0 ~ 20pt）平滑线性淡入淡出（0.0 -> 1.0）
    private var scrollProgress: CGFloat {
        min(1.0, max(0.0, scrollOffsetY / 20.0))
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, newOffset in
                scrollOffsetY = max(0, newOffset)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text(title)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    trailing()
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background {
                    headerDynamicBlurBackground
                }
            }
    }

    /// 滚动动态毛玻璃背景：
    /// 1. 静止置顶状态（scrollOffsetY == 0）：完全透明，0 遮挡内容，卡片与页面底色 100% 清晰纯净呈现；
    /// 2. 随手势连续过渡（0 ~ 20pt）：透明度随上滑位移平滑渐显（opacity: 0.0 -> 1.0）；
    /// 3. 无边框无延伸（Borderless）：严格锁定在状态栏 + 54pt 标题栏主体内，彻底消除向下 16pt 延伸遮挡；
    /// 4. 低版本/降低透明度模式：平滑淡入纯色 Color.pageBackground (#F3F3F3) 实体底色。
    @ViewBuilder
    private var headerDynamicBlurBackground: some View {
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
    /// 为 Tab 首页配置左侧大标题的 Inline 导航栏规范（无右侧操作项）
    func tabInlineNavigationTitle(_ title: String) -> some View {
        self.modifier(TabInlineHeaderModifier(title: title, trailing: { EmptyView() }))
    }

    /// 为 Tab 首页配置左侧大标题的 Inline 导航栏规范（带右侧操作项）
    func tabInlineNavigationTitle<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        self.modifier(TabInlineHeaderModifier(title: title, trailing: trailing))
    }
}
