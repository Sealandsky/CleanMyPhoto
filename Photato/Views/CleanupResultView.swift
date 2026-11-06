import SwiftUI

/// 清理完成结果弹窗页面（附带碎花彩带动画与触觉震动反馈）
struct CleanupResultView: View {
    let result: CleanupResult
    let onDismiss: () -> Void

    @State private var badgeScale: CGFloat = 0.3
    @State private var badgeOpacity: Double = 0.0
    @State private var contentOpacity: Double = 0.0
    @State private var contentOffsetY: CGFloat = 24

    var body: some View {
        ZStack {
            // 背景底色：自适应深色 / 浅色模式
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            // 碎花彩带动效全屏覆盖（打开即喷发，单次飘落自然沉降）
            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // 顶部关闭按钮栏
                topBar

                Spacer(minLength: 12)

                // 中间庆祝成果区（徽标、主标题、说明、指标卡片）
                celebrationSection

                Spacer(minLength: 24)

                // 底部「完成」主操作胶囊按钮
                bottomActionButton
            }
        }
        .onAppear {
            playEntranceAnimation()
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height > 80 && abs(value.translation.width) < value.translation.height {
                        triggerDismiss()
                    }
                }
        )
    }

    // MARK: - 顶部导航栏（保留轻量右上角关闭入口）
    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                triggerDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(uiColor: .secondarySystemFill)))
            }
            .contentShape(Circle())
            .accessibilityLabel(String(localized: "Close"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 中间庆祝内容
    private var celebrationSection: some View {
        VStack(spacing: 20) {
            // 绿色对勾徽章
            checkmarkBadge
                .scaleEffect(badgeScale)
                .opacity(badgeOpacity)

            // 主标题
            Text(String(localized: "Cleanup Complete!"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .opacity(contentOpacity)
                .offset(y: contentOffsetY)

            // 结果说明副标题
            Text(descriptionText)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 36)
                .opacity(contentOpacity)
                .offset(y: contentOffsetY)
        }
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
                .frame(width: 98, height: 98)
                .shadow(color: Color.green.opacity(0.32), radius: 16, x: 0, y: 8)

            // 对勾图标
            Image(systemName: "checkmark")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    // MARK: - 底部操作按钮
    private var bottomActionButton: some View {
        LiquidGlassCapsuleButton(
            isProminent: true,
            tintColor: .blue,
            height: 56
        ) {
            triggerDismiss()
        } label: {
            Text(String(localized: "Done"))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .opacity(contentOpacity)
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
        // 1. 成功震动反馈
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // 2. 对勾徽标弹簧弹出
        withAnimation(.spring(response: 0.48, dampingFraction: 0.64, blendDuration: 0)) {
            badgeScale = 1.0
            badgeOpacity = 1.0
        }

        // 3. 文本与按钮渐显上移
        withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
            contentOpacity = 1.0
            contentOffsetY = 0
        }
    }

    private func triggerDismiss() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onDismiss()
    }
}

#Preview {
    CleanupResultView(
        result: CleanupResult(deletedCount: 18, freedBytes: 154_892_100),
        onDismiss: {}
    )
}
