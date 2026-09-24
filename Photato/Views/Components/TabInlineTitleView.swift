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
                .padding(.vertical, 4)
                .frame(minHeight: 52)
                .background {
                    headerGradientBlurBackground
                }
            }
    }

    /// 渐变毛玻璃背景：以系统 ultraThinMaterial 为材质基底，
    /// 顶部与主体区域全强效模糊，底部向下 20pt 柔和渐隐过渡，杜绝硬切边缘。
    private var headerGradientBlurBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.72),
                        .init(color: .black.opacity(0), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .padding(.bottom, -20)
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
