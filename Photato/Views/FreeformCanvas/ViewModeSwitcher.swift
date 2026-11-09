import SwiftUI

// MARK: - 模式切换控件 (View Mode Switcher)
/// 左下角网格/画布切换：系统 TabBar 同款 Liquid Glass 浮动分段控件（Colo v1.6 规范四.2）。
/// iOS 26+：GlassEffectContainer + .glassEffect(.regular.interactive()) + glassEffectID，
/// 选中段是一整块液态玻璃高亮，切换时玻璃液从当前段流动到目标段；
/// iOS 18 回退 .regularMaterial 毛玻璃胶囊 + 白底圆选中态。
private enum CanvasViewMode: String, CaseIterable, Identifiable {
    case grid
    case canvas

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2.fill"
        case .canvas: return "photo.on.rectangle.angled"
        }
    }
}

struct ViewModeSwitcher: View {
    @Binding var isCanvasMode: Bool
    @Namespace private var glassNamespace

    var body: some View {
        if #available(iOS 26.0, *) {
            glassSegmentedSwitcher
        } else {
            legacyMaterialSwitcher
        }
    }

    // MARK: iOS 26+ 液态玻璃分段（TabBar 同款）
    @available(iOS 26.0, *)
    private var glassSegmentedSwitcher: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(CanvasViewMode.allCases) { mode in
                    segment(for: mode)
                }
            }
            .padding(4)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 5)
    }

    @available(iOS 26.0, *)
    private func segment(for mode: CanvasViewMode) -> some View {
        let isSelected = (mode == .canvas) == isCanvasMode
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isCanvasMode = (mode == .canvas)
            }
        } label: {
            Image(systemName: mode.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: 44, height: 40)
                .glassEffect(
                    isSelected ? .regular.interactive() : .clear,
                    in: .capsule
                )
                .glassEffectID(mode, in: glassNamespace)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(String(localized: mode == .grid ? "Switch to Grid View" : "Switch to Canvas View"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: iOS 18 回退毛玻璃胶囊
    private var legacyMaterialSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(CanvasViewMode.allCases) { mode in
                let isSelected = (mode == .canvas) == isCanvasMode
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isCanvasMode = (mode == .canvas)
                    }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .frame(width: 44, height: 40)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.cardBackground : .clear)
                                .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0), radius: 4, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(String(localized: mode == .grid ? "Switch to Grid View" : "Switch to Canvas View"))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}
