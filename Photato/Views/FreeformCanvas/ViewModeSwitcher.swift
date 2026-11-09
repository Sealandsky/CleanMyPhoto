import SwiftUI

// MARK: - 模式切换悬浮胶囊 (Floating View Mode Switcher)
/// 左下角网格/画布切换悬浮控件：
/// 胶囊整体 48pt 高（内边距 4pt），按钮 40×40pt、图标 15pt semibold，
/// 触控热区 44×44pt；.regularMaterial 毛玻璃 + 加强投影，对齐系统原生悬浮控件质感。
struct ViewModeSwitcher: View {
    @Binding var isCanvasMode: Bool

    var body: some View {
        HStack(spacing: 2) {
            switcherButton(icon: "square.grid.2x2.fill", active: !isCanvasMode) {
                withAnimation(.easeInOut(duration: 0.22)) { isCanvasMode = false }
            }
            .accessibilityLabel(String(localized: "Switch to Grid View"))

            switcherButton(icon: "photo.on.rectangle.angled", active: isCanvasMode) {
                withAnimation(.easeInOut(duration: 0.22)) { isCanvasMode = true }
            }
            .accessibilityLabel(String(localized: "Switch to Canvas View"))
        }
        .padding(4)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    private func switcherButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(active ? .primary : .secondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(active ? Color.cardBackground : .clear)
                        .shadow(color: Color.black.opacity(active ? 0.12 : 0), radius: 4, y: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
    }
}
