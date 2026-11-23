import SwiftUI

/// 清理完成结果面板：贴底悬浮卡（对齐自由画布引导卡的视觉语言），非全屏。
/// 半透明遮罩 + 白底大圆角卡片，高度由内容撑起；支持右上角 × 与下拉关闭。
struct CleanupResultView: View {
    let result: CleanupResult
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var backdropOpacity: Double = 0
    @State private var panelOffset: CGFloat = 70
    @State private var badgeScale: CGFloat = 0.35
    @State private var badgeOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // 半透明遮罩：隔离底层交互，点击空白处关闭
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .opacity(backdropOpacity)
                .contentShape(Rectangle())
                .onTapGesture { triggerDismiss() }

            // 贴底悬浮面板（高度由内容撑起，不可拖大）
            resultPanel
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 16)
                .padding(.bottom, 44) // 距 Home Indicator 上方留白，与画布引导卡一致
                .offset(y: dragOffset)
                .gesture(dismissDrag)
        }
        .onAppear { playEntranceAnimation() }
    }

    // MARK: - 面板本体
    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // grabber 纯视觉：面板非 sheet，向下只有「下拉关闭」，不存在拖大
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 8)

            // 成功徽章 + 环绕碎花装饰
            ZStack {
                checkmarkBadge
                    .scaleEffect(badgeScale)
                    .opacity(badgeOpacity)
                confettiDecor
                    .opacity(badgeOpacity)
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)

            // 主标题
            Text(String(localized: "Cleanup Complete!"))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .opacity(contentOpacity)
                .padding(.bottom, 8)

            // 结果说明
            Text(descriptionText)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(contentOpacity)
                .padding(.bottom, 22)

            // 底部主操作按钮
            doneButton
                .opacity(contentOpacity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white)
        )
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(.trailing, 16)
                .padding(.top, 16)
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15),
            radius: 24,
            x: 0,
            y: 10
        )
        .offset(y: panelOffset)
        .opacity(backdropOpacity)
    }

    // MARK: - 右上角关闭
    private var closeButton: some View {
        Button {
            triggerDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Close"))
    }

    // MARK: - 绿色对勾徽标
    private var checkmarkBadge: some View {
        ZStack {
            // 放射状呼吸柔光环
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.green.opacity(0.32), Color.clear],
                        center: .center,
                        startRadius: 28,
                        endRadius: 72
                    )
                )
                .frame(width: 144, height: 144)

            // 绿色渐变底圆
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.78, blue: 0.40),
                            Color(red: 0.08, green: 0.64, blue: 0.32)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 92, height: 92)
                .shadow(color: Color.green.opacity(0.32), radius: 16, x: 0, y: 8)

            // 对勾图标
            Image(systemName: "checkmark")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    // MARK: - 徽章周围的彩色碎花装饰（贴合参考图，替代全屏彩带）
    private var confettiDecor: some View {
        let colors: [Color] = [
            Color(red: 0.98, green: 0.33, blue: 0.32),
            Color(red: 0.12, green: 0.74, blue: 0.98),
            Color(red: 1.00, green: 0.82, blue: 0.20),
            Color(red: 0.98, green: 0.42, blue: 0.70),
            Color(red: 0.64, green: 0.40, blue: 0.94),
            Color(red: 0.18, green: 0.80, blue: 0.44),
            Color(red: 1.00, green: 0.54, blue: 0.16),
            Color(red: 0.28, green: 0.86, blue: 0.68)
        ]
        return ZStack {
            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) / 12.0 * 2 * Double.pi
                let radius: CGFloat = (i % 2 == 0) ? 62 : 74
                let x = CGFloat(cos(angle)) * radius
                let y = CGFloat(sin(angle)) * radius
                Group {
                    if i % 3 == 0 {
                        Capsule()
                            .fill(colors[i % colors.count])
                            .frame(width: 3, height: 11)
                            .rotationEffect(.degrees(angle * 180 / Double.pi + 90))
                    } else {
                        Circle()
                            .fill(colors[i % colors.count])
                            .frame(width: (i % 2 == 0) ? 7 : 5, height: (i % 2 == 0) ? 7 : 5)
                    }
                }
                .offset(x: x, y: y)
            }
        }
        .frame(width: 170, height: 170)
    }

    // MARK: - 底部按钮
    private var doneButton: some View {
        Button {
            triggerDismiss()
        } label: {
            Text(String(localized: "Done"))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(colorScheme == .dark ? Color.white : Color.black))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 文案计算
    private var descriptionText: String {
        if result.freedBytes > 0 {
            return String(localized: "Successfully cleaned \(result.deletedCount) photos and freed \(result.formattedBytes) of space.")
        } else {
            return String(localized: "Successfully cleaned \(result.deletedCount) photos.")
        }
    }

    // MARK: - 动效控制
    private func playEntranceAnimation() {
        // 成功震动反馈
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        withAnimation(.easeOut(duration: 0.25)) {
            backdropOpacity = 1
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
            panelOffset = 0
        }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.64, blendDuration: 0).delay(0.15)) {
            badgeScale = 1
            badgeOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
            contentOpacity = 1
        }
    }

    // MARK: - 下拉关闭：仅响应向下位移（向上不跟手 = 不可拖大）
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let shouldDismiss = dragOffset > 90
                    || value.predictedEndLocation.y - value.startLocation.y > 200
                if shouldDismiss {
                    triggerDismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func triggerDismiss() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onDismiss()
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()
        CleanupResultView(
            result: CleanupResult(deletedCount: 18, freedBytes: 154_892_100),
            onDismiss: {}
        )
    }
}
