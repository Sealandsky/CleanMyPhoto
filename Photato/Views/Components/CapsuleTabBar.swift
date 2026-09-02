import SwiftUI

// MARK: - Segment Model
/// 分段 Tab 项：图标 + 文字标题（支持 1-N 个，顺序即展示顺序）
struct CapsuleSegment: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
}

// MARK: - Capsule Tab Bar
/// 底部栏：【胶囊分段 Tab 组】+【独立圆形按钮】HStack 平级并排，固定间距，
/// 按钮在胶囊外部、不被包裹。
///
/// - Tab 组支持 1-N 个选项，每项含图标 + 文字标题
/// - 选中项内部灰色胶囊滑块，切换时经 matchedGeometryEffect 平滑滑动
/// - 选中态：蓝色图标文字；未选中：primary（浅色模式为黑色，深色模式自动反转）
/// - 背景使用系统动态颜色 systemBackground，自动适配暗黑模式，不硬编码色值
/// - 胶囊与圆钮均带柔和阴影
/// - 圆形按钮独立平级，触发外部传入的闭包动作，不参与 Tab 选择切换
///
/// iOS 26 兼容提示：将 prefersLiquidGlass 置为 true 可选开启系统 Liquid Glass
/// 背景（.glassEffect），默认关闭以保持 iOS 18 一致观感
struct CapsuleTabBar: View {
    let segments: [CapsuleSegment]
    @Binding var selectionID: String
    var accessorySystemImage: String = "trash"
    /// iOS 26+ 可选：开启 Liquid Glass 背景替代 systemBackground
    var prefersLiquidGlass: Bool = false
    /// 再次点击已选中 Tab 的回调（如：回到页面顶部）
    var onReselect: ((String) -> Void)? = nil
    let onAccessoryTap: () -> Void

    /// 滑块几何匹配命名空间（滑动动画的关键）
    @Namespace private var sliderNS

    // 动态颜色：全部使用系统语义色，自动适配深浅模式
    private var containerColor: Color { Color(.systemBackground) } // 胶囊容器底色
    private var selectedForeground: Color { .white }               // 选中：白色（深色滑块上对比恒定）
    private var unselectedForeground: Color { .primary }           // 未选中：黑色（深色模式自动白）
    private var hairlineColor: Color { Color.primary.opacity(0.08) }
    private var softShadowColor: Color { Color.black.opacity(0.12) } // 阴影专用，非前景色

    var body: some View {
        HStack(spacing: 12) {
            segmentCapsule
            accessoryButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // 容器级动画兜底：程序化修改 selectionID（非点击）时滑块同样平滑滑动
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selectionID)
    }

    // MARK: - 胶囊分段 Tab 组
    private var segmentCapsule: some View {
        HStack(spacing: 4) {
            ForEach(segments) { segment in
                let isSelected = segment.id == selectionID
                Button {
                    if segment.id == selectionID {
                        // 已选中 Tab 再次点击：不重复切换，交由外部处理（如滚回顶部）
                        onReselect?(segment.id)
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectionID = segment.id
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: segment.systemImage)
                            .font(.system(size: 19, weight: .medium))
                        Text(segment.title)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(isSelected ? selectedForeground : unselectedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if isSelected {
                            segmentSlider
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity)
        .background { containerBackgroundView(in: Capsule()) }
        .overlay(Capsule().strokeBorder(hairlineColor, lineWidth: 1))
        .shadow(color: softShadowColor, radius: 10, x: 0, y: 4)
    }

    // MARK: - 选中滑块
    /// 同一时刻仅存在一个几何源，matchedGeometryEffect 驱动其在 Tab 间平滑滑动。
    /// 选中滑块为深色半透明胶囊 + 白色细描边（深色容器上勾勒滑块轮廓），
    /// 保证白色图标与文字的对比度和选中态辨识度；
    /// 未选中项文字用 primary 跟随系统
    @ViewBuilder
    private var segmentSlider: some View {
        if prefersLiquidGlass, #available(iOS 26.0, *) {
            Capsule()
                .fill(Color.clear)
                .glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: .capsule)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                .matchedGeometryEffect(id: "segment_slider", in: sliderNS)
        } else {
            Capsule()
                .fill(Color.black.opacity(0.5))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                .matchedGeometryEffect(id: "segment_slider", in: sliderNS)
        }
    }

    // MARK: - 独立圆形按钮（平级，不参与 Tab 切换）
    private var accessoryButton: some View {
        Button {
            onAccessoryTap()
        } label: {
            Image(systemName: accessorySystemImage)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
                .frame(width: 58, height: 58)
                .background { containerBackgroundView(in: Circle(), interactive: true) }
                .shadow(color: softShadowColor, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 容器背景（iOS 26 可选 Liquid Glass）
    @ViewBuilder
    private func containerBackgroundView(in shape: some Shape, interactive: Bool = false) -> some View {
        if prefersLiquidGlass, #available(iOS 26.0, *) {
            // iOS 26+：系统 Liquid Glass 材质（regular）；interactive(true) 为
            // 独立圆钮启用触摸高亮响应
            let glass: Glass = interactive ? .regular.interactive() : .regular
            Color.clear
                .glassEffect(glass, in: shape)
        } else {
            shape.fill(containerColor)
        }
    }
}

#Preview("CapsuleTabBar") {
    ZStack {
        Color(.systemGray6).ignoresSafeArea()
        CapsuleTabBar(
            segments: [
                CapsuleSegment(id: "discover", title: "发现", systemImage: "sparkle.magnifyingglass"),
                CapsuleSegment(id: "organize", title: "整理", systemImage: "sparkles"),
                CapsuleSegment(id: "settings", title: "设置", systemImage: "gearshape"),
            ],
            selectionID: .constant("discover"),
            onAccessoryTap: {}
        )
    }
}
