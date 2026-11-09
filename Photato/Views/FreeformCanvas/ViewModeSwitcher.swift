import SwiftUI

// MARK: - 模式切换胶囊 (View Mode Switcher)
struct ViewModeSwitcher: View {
    @Binding var isCanvasMode: Bool

    var body: some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isCanvasMode = false
                }
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(!isCanvasMode ? .primary : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(!isCanvasMode ? Color.cardBackground : Color.clear)
                            .shadow(color: Color.black.opacity(!isCanvasMode ? 0.08 : 0), radius: 3, y: 1)
                    )
            }
            .accessibilityLabel(String(localized: "Switch to Grid View"))

            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isCanvasMode = true
                }
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isCanvasMode ? .primary : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isCanvasMode ? Color.cardBackground : Color.clear)
                            .shadow(color: Color.black.opacity(isCanvasMode ? 0.08 : 0), radius: 3, y: 1)
                    )
            }
            .accessibilityLabel(String(localized: "Switch to Canvas View"))
        }
        .padding(2)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }
}
