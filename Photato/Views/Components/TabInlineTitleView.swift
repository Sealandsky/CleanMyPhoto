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

    func body(content: Content) -> some View {
        content
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
                    headerGradientBlurBackground
                }
            }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// 单层渐变毛玻璃背景：
    /// 1. 现代系统（iOS 15+）且未开启降低透明度：
    ///    使用单层系统原生 .ultraThinMaterial 毛玻璃作为基底，
    ///    通过 .colorMultiply(Color.pageBackground.opacity(0.35)) 色调校准对齐 App #F3F3F3 底色（无任何纯色 overlay 叠加）；
    ///    仅使用单层材质向上覆盖状态栏并向下延伸 16pt；
    ///    对单层材质整体施加渐变遮罩（状态栏 + 54pt 标题栏主体为 100% 不透明黑，下方 16pt 为平滑淡出渐变），
    ///    彻底避免多层毛玻璃材质在接缝处产生的双层叠影与硬切线；
    /// 2. 低版本兼容性 / 开启降低透明度：回退纯色 Color.pageBackground 背景。
    @ViewBuilder
    private var headerGradientBlurBackground: some View {
        if #available(iOS 15.0, *), !reduceTransparency {
            Rectangle()
                .fill(.ultraThinMaterial)
                .colorMultiply(Color.pageBackground.opacity(0.35))
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.72),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 16)
                    }
                }
                .padding(.bottom, -16)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        } else {
            Color.pageBackground
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
