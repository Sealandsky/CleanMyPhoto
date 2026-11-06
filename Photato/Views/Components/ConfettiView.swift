import SwiftUI

/// 碎花彩带粒子形状类型
enum ConfettiShapeType: CaseIterable {
    case rectangle
    case square
    case circle
    case star
    case ribbon
}

/// 单个碎花粒子数据模型（单次喷发抛物线与空气动力学参数）
struct ConfettiParticle {
    let id: Int
    let shape: ConfettiShapeType
    let color: Color
    let size: CGSize

    // 初始位置与初速度
    let startX: CGFloat
    let startY: CGFloat
    let vx: CGFloat
    let vy: CGFloat

    // 物理参数
    let gravity: CGFloat
    let drag: CGFloat

    // 摆动与 3D 翻转参数
    let swayFrequency: Double
    let swayAmplitude: CGFloat
    let swayPhase: Double

    let spinSpeed: Double
    let flipSpeed: Double
    let flipPhase: Double
}

/// 碎花彩带特效视图：打开即单次爆发与漫天飘落，持续约 3 秒后自然沉降结束，不持续喷洒。
struct ConfettiView: View {
    @State private var particles: [ConfettiParticle]
    @State private var startDate = Date()
    @State private var isCompleted: Bool = false

    /// 动效总持续时长（秒），超时后彻底停止绘制，节约 GPU 与电量
    private let totalDuration: Double = 3.4
    /// 渐隐开始时间（秒）
    private let fadeStartTime: Double = 2.4

    private static let colors: [Color] = [
        Color(red: 0.98, green: 0.33, blue: 0.32), // 珊瑚红
        Color(red: 0.12, green: 0.74, blue: 0.98), // 天空青
        Color(red: 1.00, green: 0.82, blue: 0.20), // 阳光金黄
        Color(red: 0.98, green: 0.42, blue: 0.70), // 糖果粉
        Color(red: 0.64, green: 0.40, blue: 0.94), // 薰衣草紫
        Color(red: 0.18, green: 0.80, blue: 0.44), // 翠绿
        Color(red: 1.00, green: 0.54, blue: 0.16), // 活力橙
        Color(red: 0.28, green: 0.86, blue: 0.68)  // 薄荷绿
    ]

    init(screenSize: CGSize = ScreenSizeHelper.screenSize) {
        let size = (screenSize.width > 0 && screenSize.height > 0) ? screenSize : CGSize(width: 393, height: 852)
        _particles = State(initialValue: Self.createParticles(screenSize: size))
    }

    var body: some View {
        Group {
            if !isCompleted {
                TimelineView(.animation) { timeline in
                    Canvas { context, canvasSize in
                        let elapsed = timeline.date.timeIntervalSince(startDate)

                        // 超过总时长后终止动效
                        if elapsed > totalDuration {
                            DispatchQueue.main.async {
                                self.isCompleted = true
                            }
                            return
                        }

                        renderParticles(in: context, canvasSize: canvasSize, elapsed: elapsed)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startDate = Date()
        }
    }

    // MARK: - 初始化单次喷发粒子群（中心爆发 + 顶部漫洒混合，一次性生成）
    private static func createParticles(screenSize: CGSize) -> [ConfettiParticle] {
        var list: [ConfettiParticle] = []
        var id = 0

        let width = screenSize.width
        let height = screenSize.height
        let centerX = width * 0.5
        let centerY = height * 0.38 // 中心对勾徽标附近

        // 1. 核心环形放射喷发群：围绕中心对勾徽标 360 度向外炸开 (46 个)
        for _ in 0..<46 {
            let angle = Double.random(in: 0 ... Double.pi * 2)
            let speed = CGFloat.random(in: 260 ... 620)
            let radius = CGFloat.random(in: 48 ... 62)

            // 径向初速度，配合向上抛起偏移分量，形成舒展的彩带拱弧
            let vx = CGFloat(cos(angle)) * speed
            let vy = CGFloat(sin(angle)) * speed - CGFloat.random(in: 100 ... 220)

            let shape = pickRandomShape()
            let color = colors.randomElement() ?? .green
            let pSize = randomSize(for: shape)

            list.append(ConfettiParticle(
                id: id,
                shape: shape,
                color: color,
                size: pSize,
                startX: centerX + CGFloat(cos(angle)) * radius,
                startY: centerY + CGFloat(sin(angle)) * radius,
                vx: vx,
                vy: vy,
                gravity: CGFloat.random(in: 420 ... 600),
                drag: 0.94,
                swayFrequency: Double.random(in: 3.0 ... 6.0),
                swayAmplitude: CGFloat.random(in: 14 ... 32),
                swayPhase: Double.random(in: 0 ... Double.pi * 2),
                spinSpeed: Double.random(in: -5.0 ... 5.0),
                flipSpeed: Double.random(in: 4.0 ... 8.5),
                flipPhase: Double.random(in: 0 ... Double.pi * 2)
            ))
            id += 1
        }

        // 2. 顶部协同漫洒群：自屏幕上方同步向下飞洒 (38 个)
        for _ in 0..<38 {
            let shape = pickRandomShape()
            let color = colors.randomElement() ?? .blue
            let pSize = randomSize(for: shape)

            let startX = CGFloat.random(in: 12 ... width - 12)
            let startY = CGFloat.random(in: -height * 0.25 ... 20)
            let vx = CGFloat.random(in: -45 ... 45)
            let vy = CGFloat.random(in: 40 ... 160)

            list.append(ConfettiParticle(
                id: id,
                shape: shape,
                color: color,
                size: pSize,
                startX: startX,
                startY: startY,
                vx: vx,
                vy: vy,
                gravity: CGFloat.random(in: 320 ... 480),
                drag: 0.96,
                swayFrequency: Double.random(in: 2.2 ... 4.8),
                swayAmplitude: CGFloat.random(in: 18 ... 40),
                swayPhase: Double.random(in: 0 ... Double.pi * 2),
                spinSpeed: Double.random(in: -3.5 ... 3.5),
                flipSpeed: Double.random(in: 3.5 ... 7.0),
                flipPhase: Double.random(in: 0 ... Double.pi * 2)
            ))
            id += 1
        }

        return list
    }

    private static func pickRandomShape() -> ConfettiShapeType {
        let pool: [ConfettiShapeType] = [
            .rectangle, .rectangle,
            .square,
            .circle, .circle,
            .star,
            .ribbon, .ribbon
        ]
        return pool.randomElement() ?? .rectangle
    }

    private static func randomSize(for shape: ConfettiShapeType) -> CGSize {
        switch shape {
        case .rectangle:
            return CGSize(width: CGFloat.random(in: 8 ... 12), height: CGFloat.random(in: 12 ... 19))
        case .square:
            let s = CGFloat.random(in: 8 ... 12)
            return CGSize(width: s, height: s)
        case .circle:
            let s = CGFloat.random(in: 7 ... 11)
            return CGSize(width: s, height: s)
        case .star:
            let s = CGFloat.random(in: 11 ... 16)
            return CGSize(width: s, height: s)
        case .ribbon:
            return CGSize(width: CGFloat.random(in: 14 ... 24), height: CGFloat.random(in: 28 ... 42))
        }
    }

    // MARK: - 渲染单帧
    private func renderParticles(in context: GraphicsContext, canvasSize: CGSize, elapsed: Double) {
        guard !particles.isEmpty, canvasSize.height > 0 else { return }

        // 计算全局渐隐透明度（在 2.4s ~ 3.4s 期间平滑淡出，之后停止）
        var globalFade: Double = 1.0
        if elapsed > fadeStartTime {
            let fadeProgress = (elapsed - fadeStartTime) / (totalDuration - fadeStartTime)
            globalFade = max(0, 1.0 - fadeProgress)
        }

        let t = CGFloat(elapsed)

        for p in particles {
            // 空气阻尼衰减因子
            let dragFactor = pow(p.drag, t * 60)

            // 水平位置：初速度扩散 + 正弦飘动
            let sway = sin(elapsed * p.swayFrequency + p.swayPhase) * Double(p.swayAmplitude)
            let posX = p.startX + (p.vx * dragFactor * t) + CGFloat(sway)

            // 垂直位置：初速度 + 重力加速度抛物线下落（单次下落，不循环重置）
            let posY = p.startY + (p.vy * dragFactor * t) + (0.5 * p.gravity * t * t)

            // 超出屏幕下边缘即自然剔除，不再重绘
            if posY > canvasSize.height + 60 {
                continue
            }

            // 屏幕范围保护
            guard posX >= -50 && posX <= canvasSize.width + 50 && posY >= -100 else {
                continue
            }

            // 3D 纸片翻滚模拟：水平 scaleX 在 -1 ... 1 之间余弦振荡，呈现薄纸翻转立体光影
            let scaleX = CGFloat(cos(elapsed * p.flipSpeed + p.flipPhase))
            let rotation = p.spinSpeed * elapsed

            var pContext = context
            pContext.opacity = globalFade
            pContext.translateBy(x: posX, y: posY)
            pContext.rotate(by: Angle(radians: rotation))
            pContext.scaleBy(x: scaleX, y: 1.0)

            drawShape(p.shape, size: p.size, color: p.color, in: &pContext)
        }
    }

    // MARK: - 绘制具体形状
    private func drawShape(_ shape: ConfettiShapeType, size: CGSize, color: Color, in context: inout GraphicsContext) {
        let halfW = size.width * 0.5
        let halfH = size.height * 0.5

        switch shape {
        case .rectangle, .square:
            let rect = CGRect(x: -halfW, y: -halfH, width: size.width, height: size.height)
            let path = Path(roundedRect: rect, cornerRadius: 1.5)
            context.fill(path, with: .color(color))

        case .circle:
            let rect = CGRect(x: -halfW, y: -halfH, width: size.width, height: size.height)
            let path = Path(ellipseIn: rect)
            context.fill(path, with: .color(color))

        case .star:
            let starPath = makeStarPath(size: size)
            context.fill(starPath, with: .color(color))

        case .ribbon:
            // S 形波浪卷彩带
            var path = Path()
            path.move(to: CGPoint(x: -halfW, y: -halfH))
            path.addCurve(
                to: CGPoint(x: halfW, y: halfH),
                control1: CGPoint(x: halfW * 1.5, y: -halfH * 0.2),
                control2: CGPoint(x: -halfW * 1.5, y: halfH * 0.2)
            )
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
            )
        }
    }

    private func makeStarPath(size: CGSize) -> Path {
        var path = Path()
        let points = 5
        let outerRadius = min(size.width, size.height) * 0.5
        let innerRadius = outerRadius * 0.42
        let step = Double.pi / Double(points)
        var angle = -Double.pi * 0.5

        for i in 0..<(points * 2) {
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let x = CGFloat(cos(angle)) * radius
            let y = CGFloat(sin(angle)) * radius
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
            angle += step
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ConfettiView()
    }
}
