import SwiftUI

/// 统一的系统原生 Liquid Glass 全圆角胶囊按钮组件
/// 直接使用系统 `.glass` 与 `.glassProminent` 样式，保证纯正系统原生 Liquid Glass 效果与完美对齐尺寸
struct LiquidGlassCapsuleButton<Label: View>: View {
    var isProminent: Bool = false
    var tintColor: Color = .blue
    var height: CGFloat = 56
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(
        isProminent: Bool = false,
        tintColor: Color = .blue,
        height: CGFloat = 56,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.isProminent = isProminent
        self.tintColor = tintColor
        self.height = height
        self.action = action
        self.label = label
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            if isProminent {
                Button(action: action) {
                    label()
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
                .buttonStyle(.glassProminent)
                .tint(tintColor)
                .buttonBorderShape(.capsule)
            } else {
                Button(action: action) {
                    label()
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
        } else {
            Button(action: action) {
                label()
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(isProminent ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background {
                        if isProminent {
                            Capsule().fill(tintColor)
                        } else {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                    .overlay(
                        Capsule()
                            .strokeBorder(isProminent ? Color.white.opacity(0.3) : Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            }
            .buttonStyle(LiquidGlassPressAnimationStyle())
        }
    }
}

/// 旧系统 Liquid Glass 胶囊按钮按压反馈动效
struct LiquidGlassPressAnimationStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
