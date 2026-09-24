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

    /// 渐变高斯模糊背景：
    /// 1. 主体区域（状态栏 + 54pt 标题栏）：以系统原生 .ultraThinMaterial 毛玻璃为基底，
    ///    使用 .colorMultiply(Color.pageBackground.opacity(0.35)) 色调校准对齐 App #F3F3F3 底色，
    ///    主体区域不添加遮罩，确保大标题与操作按钮的高可读性；
    /// 2. 下方额外延伸 16pt 渐变过渡区：仅对此 16pt 区域添加自上而下的 LinearGradient 遮罩
    ///    [0: 1.0, 0.72: 1.0, 1.0: 0.0]，消除底部硬分割线，内容上滑时毛玻璃平滑淡出。
    private var headerGradientBlurBackground: some View {
        ZStack(alignment: .bottom) {
            // 向上覆盖状态栏并覆盖 54pt 标题栏主体（无遮罩）
            Rectangle()
                .fill(.ultraThinMaterial)
                .colorMultiply(Color.pageBackground.opacity(0.35))
                .ignoresSafeArea(edges: .top)

            // 向下额外延伸 16pt 渐变过渡区（仅此 16pt 添加遮罩）
            Rectangle()
                .fill(.ultraThinMaterial)
                .colorMultiply(Color.pageBackground.opacity(0.35))
                .frame(height: 16)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.72),
                            .init(color: .black.opacity(0), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .offset(y: 16)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
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
