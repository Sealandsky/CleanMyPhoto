import SwiftUI
import UIKit

// MARK: - 画布左下角悬浮控件统一几何
/// 「模式切换胶囊」与「定位按钮」共用同一组尺寸：两者视觉等高，视觉成套。
/// iOS 27 模拟器逐帧实测（2026-11-10 探针，见 native-uitabbar-swiftui-hosting 记忆）：
/// - 独立 UITabBar 自动渲染 Liquid Glass 浮动胶囊，2 tab = 188 × 62pt，单键 94 × 54pt，
///   选中态为系统液态透镜（_UILiquidLensView），按住形变系统自带。
/// - 胶囊在 bar 内水平居中、顶部对齐，左右各 21pt 内部边距，无法用公开 API 去除。
/// - bar 高度低于 83pt 退化为 41pt 紧凑态（按钮 33pt，低于触控下限），故 bar 必须 83pt 高。
/// - 「胶囊 + 分离圆形按钮」的系统搜索形态（_UITabBarAuxiliaryView）在独立 bar /
///   UITabBarController + UISearchTab 两种路径下都只存在于视图树、渲染为隐藏，
///   搜索项实际内联成胶囊第三段——公开 API 拿不到分裂圆，定位按钮只能自绘系统玻璃圆。
/// 2026-11-11 需求：整套控件稍微缩小 + 位置下移。胶囊的系统自然尺寸不可改，
/// 用等比缩放渲染（仍是真系统玻璃，只是变小）；定位按钮直接用缩小后的直径。
enum CanvasFloatingControlMetrics {
    /// 胶囊（两个 tab）的系统自然尺寸：布局框按它搭，公开 API 不可改
    static let platterWidth: CGFloat = 188
    static let platterHeight: CGFloat = 62
    /// 控件统一目标视觉高度：胶囊缩放到它、定位按钮直径取它
    static let visualHeight: CGFloat = 56
    /// 胶囊渲染缩放比（锚定底边，保证与定位按钮底边对齐）
    static let controlScale: CGFloat = visualHeight / platterHeight
    /// 定位按钮直径，与胶囊缩小后的视觉高度等高
    static let locatorSize: CGFloat = visualHeight
    /// 胶囊与定位按钮之间的布局间距：胶囊居中缩放后布局框左右各内缩
    /// (1 - controlScale) / 2 × platterWidth ≈ 9.5pt，视觉间隙 = 布局间距 + 内缩；
    /// 按目标视觉间隙 ~14.5pt 反推出布局间距 5
    static let splitGap: CGFloat = 5
    /// 距屏幕物理底边的间距：忽略底部安全区，自行控制悬浮高度。
    /// 实测校准（iPhone 18 Pro）：间距 - 51 ≈ 胶囊底边距物理底边距离。
    /// 2026-11-11 逐步下移验证：78（底边 ≈27pt）→ 56（底边 ≈5pt，贴近 Home Indicator）。
    static let bottomInset: CGFloat = 56
    /// iOS 18 回退胶囊内边距
    static let legacyPadding: CGFloat = 4
    /// iOS 18 回退胶囊符号字号
    static let legacySymbolPointSize: CGFloat = 15
    /// iOS 18 回退胶囊单段按钮高度（整体缩到目标视觉高度 56）
    static var legacyButtonHeight: CGFloat { visualHeight - legacyPadding * 2 }
    /// iOS 18 回退胶囊单段按钮宽度（两段 + 间距 + 内边距 ≈ 缩放后的胶囊宽 169pt）
    static var legacyButtonWidth: CGFloat { (platterWidth * controlScale - legacyPadding * 2 - 2) / 2 }
}

// MARK: - 模式切换控件 (View Mode Switcher)
/// 左下角网格/画布切换：
/// - iOS 26+ 用真 UITabBar（用户 2026-11-09 决策：能用系统控件就别做视觉仿制；
///   自绘玻璃与系统分段控件都先后被否——前者按住无液态玻璃，后者不是 tab bar 形态）。
///   液态玻璃胶囊、选中液态透镜、按住形变全部系统自带。
/// - iOS 18 回退 .regularMaterial 毛玻璃胶囊 + 白底圆选中态。
private enum CanvasViewMode: Int, CaseIterable {
    // 2026-11-11 需求：自由画布在左、列表（网格）在右；默认进入的画布形态排在首位
    case canvas = 0
    case grid = 1

    var icon: String {
        switch self {
        case .grid: return "rectangle.grid.2x2.fill"
        case .canvas: return "rectangle.3.group.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .grid: return String(localized: "Switch to Grid View")
        case .canvas: return String(localized: "Switch to Canvas View")
        }
    }
}

struct ViewModeSwitcher: View {
    @Binding var isCanvasMode: Bool

    var body: some View {
        if #available(iOS 26.0, *) {
            NativeTabBarSwitcherHost(isCanvasMode: $isCanvasMode)
                .frame(
                    width: CanvasFloatingControlMetrics.platterWidth,
                    height: CanvasFloatingControlMetrics.platterHeight
                )
                // 系统胶囊尺寸公开 API 不可改：等比缩放到目标视觉高度。
                // 锚定底边与定位按钮底边对齐；缩放后的命中区域 SwiftUI 按变换后区域算。
                .scaleEffect(CanvasFloatingControlMetrics.controlScale, anchor: .bottom)
        } else {
            legacyMaterialSwitcher
        }
    }

    /// 选中滑块左右滑动的弹簧曲线：贴近 Liquid Glass 控件的液态手感。
    static let modeSelectionAnimation: Animation =
        .spring(response: 0.3, dampingFraction: 0.82, blendDuration: 0.12)

    // MARK: iOS 18 回退毛玻璃胶囊
    /// 白色圆选中态用 matchedGeometryEffect 在两 tab 间左右滑动，
    /// 保证与 iOS 26 系统透镜的滑动切换手感方向一致。
    @Namespace private var selectionNamespace

    private var legacyMaterialSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(CanvasViewMode.allCases, id: \.rawValue) { mode in
                let isSelected = (mode == .canvas) == isCanvasMode
                Button {
                    withAnimation(ViewModeSwitcher.modeSelectionAnimation) {
                        isCanvasMode = (mode == .canvas)
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(Color.cardBackground)
                                .shadow(color: Color.black.opacity(0.12), radius: 4, y: 1)
                                .matchedGeometryEffect(id: "modeSelection", in: selectionNamespace)
                        }
                        Image(systemName: mode.icon)
                            .font(.system(size: CanvasFloatingControlMetrics.legacySymbolPointSize, weight: .semibold))
                            .foregroundColor(isSelected ? .primary : .secondary)
                    }
                    .frame(
                        width: CanvasFloatingControlMetrics.legacyButtonWidth,
                        height: CanvasFloatingControlMetrics.legacyButtonHeight
                    )
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(mode.accessibilityLabel)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(CanvasFloatingControlMetrics.legacyPadding)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

// MARK: - iOS 26+ 真 UITabBar 宿主
/// 独立 UITabBar（无 UITabBarController）在 iOS 26+ 自动渲染 Liquid Glass 浮动胶囊。
/// 布局技巧（iOS 27 实测常量）：交给 SwiftUI 的容器恰好等于胶囊 188 × 62pt；
/// bar 本体放在 x = -21、宽 +42、高 83 向四周外溢——胶囊在 bar 内居中抵消 21pt 内边距，
/// 83pt 高避免紧凑态退化；外溢区在容器 bounds 之外，不参与命中测试，不影响旁边的定位按钮。
/// 胶囊区（容器 0..188 × 0..62）完整落在容器内，两枚 tab 正常点击。
@available(iOS 26.0, *)
struct NativeTabBarSwitcherHost: UIViewRepresentable {
    @Binding var isCanvasMode: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let bar = UITabBar()
        bar.frame = CGRect(
            x: -21,
            y: 0,
            width: CanvasFloatingControlMetrics.platterWidth + 42,
            height: 83
        )
        bar.delegate = context.coordinator

        let items = CanvasViewMode.allCases.map { mode in
            let item = UITabBarItem(
                title: nil,
                image: UIImage(systemName: mode.icon),
                tag: mode.rawValue
            )
            item.accessibilityLabel = mode.accessibilityLabel
            return item
        }
        bar.setItems(items, animated: false)
        bar.selectedItem = items[isCanvasMode ? CanvasViewMode.canvas.rawValue : CanvasViewMode.grid.rawValue]

        container.addSubview(bar)
        context.coordinator.bar = bar
        context.coordinator.items = items
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.parent = self
        // 外部（如画布复位逻辑）改变模式时，把系统胶囊选中态同步过去；
        // 程序化设置 selectedItem 不会触发 delegate，无回环。
        let expected = context.coordinator.items[isCanvasMode ? CanvasViewMode.canvas.rawValue : CanvasViewMode.grid.rawValue]
        if context.coordinator.bar?.selectedItem !== expected {
            context.coordinator.bar?.selectedItem = expected
        }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var parent: NativeTabBarSwitcherHost
        weak var bar: UITabBar?
        var items: [UITabBarItem] = []

        init(_ parent: NativeTabBarSwitcherHost) {
            self.parent = parent
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            let newValue = item.tag == CanvasViewMode.canvas.rawValue
            guard newValue != parent.isCanvasMode else { return }
            withAnimation(ViewModeSwitcher.modeSelectionAnimation) {
                parent.isCanvasMode = newValue
            }
        }
    }
}
