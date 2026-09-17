import SwiftUI

struct ShimmerModifier: ViewModifier {
    var cornerRadius: CGFloat? = nil
    @Environment(\.colorScheme) private var colorScheme

    // 扫光节奏：全程斜向单次扫光 1.3s + 静止等待 1.1s = 总周期 2.4s
    private static let sweepDuration: Double = 1.3
    private static let pauseDuration: Double = 1.1
    private static let totalCycle: Double = sweepDuration + pauseDuration

    func body(content: Content) -> some View {
        content
            .overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let timeInCycle = now.truncatingRemainder(dividingBy: Self.totalCycle)
                    let isSweeping = timeInCycle < Self.sweepDuration

                    // 进度计算：仅在扫光阶段前进，在等待阶段归入终点外侧
                    let progress: CGFloat = {
                        if isSweeping {
                            let t = timeInCycle / Self.sweepDuration
                            // Smoothstep (3t^2 - 2t^3) 平滑加减速，从色块上方外柔和进入、再从右下角平滑出去
                            return CGFloat(t * t * (3.0 - 2.0 * t))
                        } else {
                            return 1.0
                        }
                    }()

                    // 轨迹范围：从上方外侧 c = -0.9 完整滑入，并从右下角外侧 c = 1.9 完整滑出，全程不截断
                    let c: CGFloat = -0.9 + progress * 2.8

                    let highlightColor = colorScheme == .dark
                        ? Color.white.opacity(0.35)
                        : Color.white.opacity(0.80)

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: highlightColor.opacity(0.25), location: 0.28),
                            .init(color: highlightColor, location: 0.50),
                            .init(color: highlightColor.opacity(0.25), location: 0.72),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: UnitPoint(x: c - 0.45, y: c - 0.65),
                        endPoint: UnitPoint(x: c + 0.45, y: c + 0.65)
                    )
                    .opacity(isSweeping ? 1.0 : 0.0)
                }
                .allowsHitTesting(false)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius ?? 16,
                    style: .continuous
                )
            )
    }
}

extension View {
    func shimmering(cornerRadius: CGFloat? = nil) -> some View {
        modifier(ShimmerModifier(cornerRadius: cornerRadius))
    }
}
