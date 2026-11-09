import SwiftUI

// MARK: - 模式切换悬浮胶囊 (Floating View Mode Switcher)
struct ViewModeSwitcher: View {
    @Binding var isCanvasMode: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isCanvasMode = false
                }
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(!isCanvasMode ? .primary : .secondary)
                    .frame(width: 38, height: 32)
                    .background(
                        Capsule()
                            .fill(!isCanvasMode ? (colorScheme == .dark ? Color(white: 0.25) : Color.white) : Color.clear)
                            .shadow(color: Color.black.opacity(!isCanvasMode ? (colorScheme == .dark ? 0.3 : 0.12) : 0), radius: 4, y: 1.5)
                    )
            }
            .accessibilityLabel(String(localized: "Switch to Grid View"))

            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isCanvasMode = true
                }
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isCanvasMode ? .primary : .secondary)
                    .frame(width: 38, height: 32)
                    .background(
                        Capsule()
                            .fill(isCanvasMode ? (colorScheme == .dark ? Color(white: 0.25) : Color.white) : Color.clear)
                            .shadow(color: Color.black.opacity(isCanvasMode ? (colorScheme == .dark ? 0.3 : 0.12) : 0), radius: 4, y: 1.5)
                    )
            }
            .accessibilityLabel(String(localized: "Switch to Canvas View"))
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.primary.opacity(0.06), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 10, y: 4)
    }
}
