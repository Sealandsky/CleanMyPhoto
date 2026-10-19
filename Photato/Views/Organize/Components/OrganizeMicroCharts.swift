import SwiftUI

// MARK: - 1. 环形进度圈 (Circular Gauge)
/// 参考 Calories / Water 卡片的圆环进度展示，外带柔和背景底轨与高饱和渐变弧线
struct CircularGaugeView: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 4.5
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            // 背景轨道
            Circle()
                .stroke(color.opacity(0.14), lineWidth: lineWidth)

            // 进度弧线
            Circle()
                .trim(from: 0, to: max(0.06, min(1.0, progress)))
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.75), color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 2. 迷你柱状图 Sparkline (Mini Bar Sparkline)
/// 参考 Sleep 卡片右侧的垂直迷你条形图，高光峰值柱与柔和浅色柱交错律动
struct MiniBarSparklineView: View {
    let color: Color
    var heightRatios: [CGFloat] = [0.38, 0.68, 0.50, 1.0, 0.72]
    var peakIndex: Int = 3
    var size: CGSize = CGSize(width: 40, height: 30)

    var body: some View {
        HStack(alignment: .bottom, spacing: 3.5) {
            ForEach(0..<min(5, heightRatios.count), id: \.self) { idx in
                let isPeak = (idx == peakIndex)
                Capsule(style: .continuous)
                    .fill(isPeak ? color : color.opacity(0.22))
                    .frame(width: 3.5, height: max(6, size.height * heightRatios[idx]))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
    }
}

// MARK: - 3. 柔滑波形图 Sparkline (Mini Wave Sparkline)
/// 参考 Weight 卡片右侧的贝塞尔平滑波形曲线与渐变投影底色
struct MiniWaveSparklineView: View {
    let color: Color
    var size: CGSize = CGSize(width: 44, height: 28)

    var body: some View {
        ZStack(alignment: .bottom) {
            // 曲线下方淡雅渐变面积填充
            WaveFillShape()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.25), color.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 柔滑主曲线
            WaveLineShape()
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                )
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - 曲线形状实现
private struct WaveLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startY = rect.height * 0.85
        path.move(to: CGPoint(x: 0, y: startY))

        // 第一段向上爬升
        path.addCurve(
            to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.30),
            control1: CGPoint(x: rect.width * 0.14, y: rect.height * 0.82),
            control2: CGPoint(x: rect.width * 0.22, y: rect.height * 0.30)
        )

        // 中间轻微波谷
        path.addCurve(
            to: CGPoint(x: rect.width * 0.68, y: rect.height * 0.60),
            control1: CGPoint(x: rect.width * 0.48, y: rect.height * 0.30),
            control2: CGPoint(x: rect.width * 0.58, y: rect.height * 0.60)
        )

        // 尾部冲向高点
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.18),
            control1: CGPoint(x: rect.width * 0.82, y: rect.height * 0.60),
            control2: CGPoint(x: rect.width * 0.90, y: rect.height * 0.18)
        )

        return path
    }
}

private struct WaveFillShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = WaveLineShape().path(in: rect)
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - 4. 英雄胶囊柱状图 (Hero Bar Chart)
/// 参考截图 1 顶部「Steps」大卡片中的 9 根圆角胶囊柱状图与浮动黑胶囊数值气泡
struct HeroBarItem: Identifiable, Sendable {
    let id: String
    let icon: String
    let title: String
    let count: Int
    let relativeHeight: CGFloat
    let tintColor: Color
}

struct HeroBarChartView: View {
    let items: [HeroBarItem]
    @Binding var selectedIndex: Int
    var isAnalyzing: Bool = false
    var onSelectBar: ((Int) -> Void)? = nil

    private let chartHeight: CGFloat = 68
    private let barWidth: CGFloat = 18

    // 活跃渐变（参考 Steps 卡片的高饱和绿渐变）
    private static let activeGradient = LinearGradient(
        colors: [
            Color(red: 0.62, green: 0.94, blue: 0.22),
            Color(red: 0.16, green: 0.78, blue: 0.24)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        VStack(spacing: 8) {
            // 柱子区域 + 顶部气泡
            ZStack(alignment: .bottom) {
                // 柱子阵列
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        barColumn(index: index, item: item)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: chartHeight)

                // 悬浮在当前高亮柱顶部的深色胶囊气泡（带向下小箭头）
                if !items.isEmpty && selectedIndex >= 0 && selectedIndex < items.count {
                    tooltipBadge(for: items[selectedIndex], at: selectedIndex)
                }
            }

            // 底部图标/类别标签行
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isSelected = (index == selectedIndex)
                    Image(systemName: item.icon)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? item.tintColor : Color(.tertiaryLabel))
                        .frame(maxWidth: .infinity)
                        .scaleEffect(isSelected ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                }
            }
        }
    }

    private func barColumn(index: Int, item: HeroBarItem) -> some View {
        let isSelected = (index == selectedIndex)
        // 确保有最小高度（0 也有基础胶囊体），最大占满 chartHeight
        let targetHeight = isAnalyzing
            ? pulsatingHeight(for: index)
            : max(16, chartHeight * max(0.18, min(1.0, item.relativeHeight)))

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedIndex = index
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelectBar?(index)
        } label: {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(Self.activeGradient)
                            : AnyShapeStyle(Color(.systemGray5).opacity(0.85))
                    )
                    .frame(width: barWidth, height: targetHeight)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                isSelected ? Color.white.opacity(0.4) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    .shadow(
                        color: isSelected ? Color(red: 0.2, green: 0.8, blue: 0.25).opacity(0.28) : .clear,
                        radius: 6,
                        y: 3
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 浮动在选中柱子上方的数据提示气泡
    private func tooltipBadge(for item: HeroBarItem, at index: Int) -> some View {
        GeometryReader { geo in
            let totalCount = max(1, items.count)
            let stepWidth = geo.size.width / CGFloat(totalCount)
            let centerX = stepWidth * (CGFloat(index) + 0.5)
            let barH = max(16, chartHeight * max(0.18, min(1.0, item.relativeHeight)))
            let badgeY = chartHeight - barH - 18

            VStack(spacing: -1) {
                // 黑色小胶囊
                HStack(spacing: 3) {
                    Text("\(item.count.formatted())")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
                )
                .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)

                // 向下倒三角微小连接角
                TooltipArrow()
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .frame(width: 7, height: 4)
            }
            .position(x: centerX, y: max(10, badgeY))
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: selectedIndex)
        }
        .frame(height: chartHeight)
        .allowsHitTesting(false)
    }

    private func pulsatingHeight(for index: Int) -> CGFloat {
        let pattern: [CGFloat] = [0.35, 0.7, 0.45, 0.9, 0.6, 0.85, 0.4, 0.75, 0.5]
        let base = pattern[index % pattern.count]
        return max(16, chartHeight * base)
    }
}

// 倒三角箭头
private struct TooltipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width / 2, y: rect.height))
        path.closeSubpath()
        return path
    }
}
