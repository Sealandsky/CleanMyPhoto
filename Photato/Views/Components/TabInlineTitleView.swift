import SwiftUI
import UIKit

/// Tab 首页通用左侧大标题视图与修饰器：
/// 在 inline 吸顶模式下，于左侧呈现原生 .largeTitle 粗体圆角大标题，
/// 右侧操作按钮采用系统 Liquid Glass 效果，背景采用向下柔和淡出的渐变毛玻璃。
struct TabInlineTitleView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.title, design: .rounded).weight(.bold))
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

// MARK: - 真实渐变高斯模糊视图（100% 官方公开 API）
/// 通过 UIKit 的 UIVisualEffectView.maskView 机制，
/// 完美克服 SwiftUI .mask 会强制抹除 Material 高斯模糊的底层限制，
/// 真正实现：既有真实高斯模糊，又自上而下平滑衰减至完全透明！
public struct GradientBlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemThinMaterial
    var solidCoverageRatio: NSNumber = 0.25 // 顶部状态栏保持 100% 饱满模糊的比例

    public init(style: UIBlurEffect.Style = .systemThinMaterial, solidCoverageRatio: NSNumber = 0.25) {
        self.style = style
        self.solidCoverageRatio = solidCoverageRatio
    }

    public func makeUIView(context: Context) -> UIGradientBlurEffectView {
        let view = UIGradientBlurEffectView(effect: UIBlurEffect(style: style))
        view.solidCoverageRatio = solidCoverageRatio
        return view
    }

    public func updateUIView(_ uiView: UIGradientBlurEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
        uiView.solidCoverageRatio = solidCoverageRatio
        uiView.setNeedsLayout()
    }
}

public class UIGradientBlurEffectView: UIVisualEffectView {
    var solidCoverageRatio: NSNumber = 0.25

    private let maskContainerView = UIView()
    private let gradientLayer = CAGradientLayer()

    override init(effect: UIVisualEffect?) {
        super.init(effect: effect)
        setupMask()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMask()
    }

    private func setupMask() {
        maskContainerView.backgroundColor = .clear
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        maskContainerView.layer.addSublayer(gradientLayer)
        self.mask = maskContainerView
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        maskContainerView.frame = self.bounds
        gradientLayer.frame = maskContainerView.bounds

        // 核心技术：在 UIKit 中，向 maskView 赋予黑到透明的 gradientLayer，
        // 能在完整保留真实高斯模糊计算的前提下，实现平滑渐进衰减！
        gradientLayer.colors = [
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            UIColor.clear.cgColor
        ]
        gradientLayer.locations = [
            0.0,
            solidCoverageRatio,
            1.0
        ]
    }
}

// MARK: - Tab Inline 导航栏修饰器
struct TabInlineHeaderModifier<Trailing: View>: ViewModifier {
    let title: String
    var titleColor: Color = .primary
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text(title)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    trailing()
                        .foregroundColor(titleColor)
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background {
                    headerDynamicBlurBackground
                }
            }
    }

    /// 真实渐进式高斯模糊背景：
    /// 既保持 100% 真实的磨砂高斯模糊折射，又从屏幕顶端向底沿平滑衰减至完全透明！
    /// 严格贴合 54pt 标题栏底边，无任何向下多余延伸，彻底杜绝遮挡下方卡片。
    @ViewBuilder
    private var headerDynamicBlurBackground: some View {
        Group {
            if #available(iOS 15.0, *), !reduceTransparency {
                GradientBlurView(style: .systemThinMaterial, solidCoverageRatio: 0.25)
                    .overlay(Color.pageBackground.opacity(0.08))
            } else {
                Color.pageBackground
            }
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

extension View {
    /// 为 Tab 首页配置左侧大标题的 Inline 导航栏规范（无右侧操作项）
    func tabInlineNavigationTitle(_ title: String, titleColor: Color = .primary) -> some View {
        self.modifier(TabInlineHeaderModifier(title: title, titleColor: titleColor, trailing: { EmptyView() }))
    }

    /// 为 Tab 首页配置左侧大标题的 Inline 导航栏规范（带右侧操作项）
    func tabInlineNavigationTitle<Trailing: View>(
        _ title: String,
        titleColor: Color = .primary,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        self.modifier(TabInlineHeaderModifier(title: title, titleColor: titleColor, trailing: trailing))
    }
}
