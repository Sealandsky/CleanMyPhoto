import SwiftUI
import UIKit

// MARK: - 环绕卡片数据模型（4:3 照片卡片）
public struct OrbitCardItem: Identifiable {
    public let id: String
    public var imageName: String?
    public var uiImage: UIImage?
    public var systemIcon: String?
    public var placeholderColors: [Color]?
    public var tag: String?
    
    public init(
        id: String = UUID().uuidString,
        imageName: String? = nil,
        uiImage: UIImage? = nil,
        systemIcon: String? = nil,
        placeholderColors: [Color]? = nil,
        tag: String? = nil
    ) {
        self.id = id
        self.imageName = imageName
        self.uiImage = uiImage
        self.systemIcon = systemIcon
        self.placeholderColors = placeholderColors
        self.tag = tag
    }
}

// MARK: - 页面主视图：结合上方 3D 环绕动效与下方 Welcome 原有内容
public struct OrbitingAvatarView: View {
    @AppStorage("hasShownWelcome") private var hasShownWelcome: Bool = false
    @AppStorage("hasShownMembership") private var hasShownMembership: Bool = false
    
    /// 是否展示原 WelcomePage 的应用图标（默认为 true）
    public var showAppIcon: Bool = true
    /// 自定义卡片列表（为 nil 时使用 8 张精美预设相片）
    public var customCards: [OrbitCardItem]? = nil
    /// 点击继续按钮的回调
    public var onContinue: (() -> Void)? = nil
    
    public init(
        showAppIcon: Bool = true,
        customCards: [OrbitCardItem]? = nil,
        onContinue: (() -> Void)? = nil
    ) {
        self.showAppIcon = showAppIcon
        self.customCards = customCards
        self.onContinue = onContinue
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            
            // MARK: 上方 - 3D 立体惯性环绕动效（超出屏幕两端）
            OrbitingPhotoCardsView(items: customCards)
                .frame(height: 340)
                .frame(maxWidth: .infinity)
            
            Spacer(minLength: 12)
            
            // MARK: 下方 - Welcome 页面原有内容
            VStack(spacing: 20) {
                if showAppIcon {
                    // 原应用图标容器
                    ZStack {
                        Image("WelcomeIcon")
                            .resizable()
                            .frame(width: 68, height: 68)
                            .cornerRadius(19)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.black, lineWidth: 0.5)
                                    .padding(-1.5)
                                    .opacity(0.25)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                    }
                    .transition(.opacity.combined(with: .scale))
                }
                
                // 欢迎文字（完全复用原 WelcomePage 文本与本地化 key）
                VStack(spacing: 8) {
                    Text(String(localized: "Welcome to Photato"))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(String(localized: "Maximize Your Photo Storage", defaultValue: "轻松整理照片"))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .frame(maxWidth: 280)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            
            Spacer(minLength: 20)
            
            // 底部继续按钮（复用原 PrimaryButtonStyle 样式）
            Button(action: {
                hasShownWelcome = true
                onContinue?()
            }) {
                Text(String(localized: "Continue"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }
}

// MARK: - 3D 惯性立体环绕动效组件（可单独复用）
public struct OrbitingPhotoCardsView: View {
    // 尺寸与轨道参数
    public var cardWidth: CGFloat = 124               // 卡片宽度（4:3 比例，高度 93）
    public var cardHeight: CGFloat { cardWidth * 3 / 4 }
    public var cornerRadius: CGFloat = 16             // 圆角大小
    
    public var radiusX: CGFloat = 215                 // 椭圆长轴半径（超出屏幕两端）
    public var radiusY: CGFloat = 72                  // 椭圆短轴半径
    public var tiltAngle: Double = -15                // 空间倾斜角（向右下倾斜）
    public var autoRotate: Bool = true                // 静止时是否自动慢速巡航
    public var onSelectCard: ((OrbitCardItem) -> Void)?
    
    // 预设 8 张示例卡片
    public var items: [OrbitCardItem] = [
        .init(
            imageName: "photo_sample_1",
            systemIcon: "mountain.2.fill",
            placeholderColors: [Color(red: 0.35, green: 0.55, blue: 0.95), Color(red: 0.15, green: 0.25, blue: 0.65)],
            tag: "Nature"
        ),
        .init(
            imageName: "photo_sample_2",
            systemIcon: "sunset.fill",
            placeholderColors: [Color(red: 0.98, green: 0.45, blue: 0.35), Color(red: 0.85, green: 0.20, blue: 0.45)],
            tag: "Sunset"
        ),
        .init(
            imageName: "photo_sample_3",
            systemIcon: "person.crop.rectangle.fill",
            placeholderColors: [Color(red: 0.92, green: 0.72, blue: 0.85), Color(red: 0.65, green: 0.40, blue: 0.75)],
            tag: "Portrait"
        ),
        .init(
            imageName: "photo_sample_4",
            systemIcon: "leaf.fill",
            placeholderColors: [Color(red: 0.40, green: 0.82, blue: 0.65), Color(red: 0.18, green: 0.52, blue: 0.40)],
            tag: "Forest"
        ),
        .init(
            imageName: "photo_sample_5",
            systemIcon: "water.waves",
            placeholderColors: [Color(red: 0.25, green: 0.75, blue: 0.92), Color(red: 0.10, green: 0.45, blue: 0.70)],
            tag: "Ocean"
        ),
        .init(
            imageName: "photo_sample_6",
            systemIcon: "sparkles",
            placeholderColors: [Color(red: 0.98, green: 0.82, blue: 0.45), Color(red: 0.92, green: 0.55, blue: 0.25)],
            tag: "Urban"
        ),
        .init(
            imageName: "photo_sample_7",
            systemIcon: "camera.macro",
            placeholderColors: [Color(red: 0.85, green: 0.35, blue: 0.65), Color(red: 0.45, green: 0.15, blue: 0.55)],
            tag: "Macro"
        ),
        .init(
            imageName: "photo_sample_8",
            systemIcon: "moon.stars.fill",
            placeholderColors: [Color(red: 0.16, green: 0.18, blue: 0.38), Color(red: 0.32, green: 0.18, blue: 0.52)],
            tag: "Night"
        )
    ]
    
    // 物理与手势状态
    @State private var rotationAngle: Double = 0
    @State private var angularVelocity: Double = 0
    @State private var isDragging: Bool = false
    
    @State private var lastDragLocationX: CGFloat = 0
    @State private var lastDragTime: Date = Date()
    @State private var instantVelocity: Double = 0
    
    public init(
        cardWidth: CGFloat = 124,
        cornerRadius: CGFloat = 16,
        radiusX: CGFloat = 215,
        radiusY: CGFloat = 72,
        tiltAngle: Double = -15,
        autoRotate: Bool = true,
        items: [OrbitCardItem]? = nil,
        onSelectCard: ((OrbitCardItem) -> Void)? = nil
    ) {
        self.cardWidth = cardWidth
        self.cornerRadius = cornerRadius
        self.radiusX = radiusX
        self.radiusY = radiusY
        self.tiltAngle = tiltAngle
        self.autoRotate = autoRotate
        if let customItems = items {
            self.items = customItems
        }
        self.onSelectCard = onSelectCard
    }

    public var body: some View {
        ZStack {
            // 背景柔和流体彩带
            FluidRainbowBackground()
                .frame(width: 840, height: 420)
                .blur(radius: 28)
                .opacity(0.65)

            // 环绕的 4:3 圆角矩形照片卡片群
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let baseAngle = Double(index) / Double(items.count) * 360
                let totalAngle = (baseAngle + rotationAngle).truncatingRemainder(dividingBy: 360)
                
                OrbitCardItemView(
                    item: item,
                    angle: totalAngle,
                    radiusX: radiusX,
                    radiusY: radiusY,
                    tiltAngle: tiltAngle,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    cornerRadius: cornerRadius
                )
                .onTapGesture {
                    onSelectCard?(item)
                }
            }
        }
        .frame(height: 340)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        // 物理滑行循环（支持离手速度甩动与无缝抓停）
        .task(id: isDragging) {
            guard !isDragging else { return }
            var lastTick = Date()
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_666_667) // ~60fps
                let now = Date()
                let dt = min(now.timeIntervalSince(lastTick), 0.05)
                lastTick = now
                
                if abs(angularVelocity) > 1.5 {
                    // 惯性滑行动量衰减
                    rotationAngle += angularVelocity * dt
                    angularVelocity *= pow(0.92, dt * 60)
                } else {
                    // 静止后优雅自转
                    angularVelocity = 0
                    if autoRotate {
                        rotationAngle += 9.0 * dt // 9度/秒 慢速巡航
                    }
                }
            }
        }
    }
    
    // MARK: - 手势物理捕捉
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let now = Date()
                if !isDragging {
                    isDragging = true
                    angularVelocity = 0 // 手指按下一瞬间立即抓停，杜绝跳变
                    lastDragLocationX = value.location.x
                    lastDragTime = now
                    instantVelocity = 0
                } else {
                    let dx = value.location.x - lastDragLocationX
                    let dt = max(now.timeIntervalSince(lastDragTime), 0.001)
                    
                    let deltaAngle = Double(dx) * 0.38
                    rotationAngle += deltaAngle
                    
                    let currentV = deltaAngle / dt
                    instantVelocity = instantVelocity * 0.3 + currentV * 0.7
                    
                    lastDragLocationX = value.location.x
                    lastDragTime = now
                }
            }
            .onEnded { _ in
                isDragging = false
                if Date().timeIntervalSince(lastDragTime) > 0.12 {
                    angularVelocity = 0
                } else {
                    let maxSpeed: Double = 650
                    angularVelocity = max(-maxSpeed, min(maxSpeed, instantVelocity))
                }
            }
    }
}

// MARK: - 单个 4:3 照片卡片渲染（空间倾斜轨迹 + Billboard 广告牌保持水平朝向）
private struct OrbitCardItemView: View {
    let item: OrbitCardItem
    let angle: Double
    let radiusX: CGFloat
    let radiusY: CGFloat
    let tiltAngle: Double
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cornerRadius: CGFloat
    
    var body: some View {
        let rad = angle * .pi / 180
        // 1. 基础椭圆
        let x0 = radiusX * cos(rad)
        let y0 = radiusY * sin(rad)
        
        // 2. 倾斜矩阵旋转
        let tiltRad = tiltAngle * .pi / 180
        let screenX = x0 * cos(tiltRad) - y0 * sin(tiltRad)
        let screenY = x0 * sin(tiltRad) + y0 * cos(tiltRad)
        
        // 3. 深度计算（sin 为 1 时最靠前，-1 时最靠后）
        let depth = (sin(rad) + 1.0) / 2.0 // 0.0 (最远) ~ 1.0 (最近)
        
        // 4. 景深参数映射
        let scale = 0.62 + depth * 0.50       // 0.62x ~ 1.12x 近大远小立体纵深
        let opacity = 0.70 + depth * 0.30     // 远景轻微半透
        let shadowRadius = 5.0 + depth * 16.0 // 前排卡片投射更柔和的深沉阴影
        let shadowY = 3.0 + depth * 10.0
        
        PhotoCardContentView(
            item: item,
            width: cardWidth,
            height: cardHeight,
            cornerRadius: cornerRadius
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .shadow(color: .black.opacity(0.18 * depth + 0.06), radius: shadowRadius, x: 0, y: shadowY)
        .offset(x: screenX, y: screenY)
        .zIndex(depth) // 确保前排照片自然遮挡后排
    }
}

// MARK: - 4:3 圆角矩形照片内容组件
private struct PhotoCardContentView: View {
    let item: OrbitCardItem
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    
    var body: some View {
        ZStack {
            // 1. 底层图片显示逻辑
            if let uiImage = item.uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let imageName = item.imageName, let img = UIImage(named: imageName) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                // 优雅占位：拟真摄影主题渐变 + 图标
                ZStack {
                    LinearGradient(
                        colors: item.placeholderColors ?? [Color.blue.opacity(0.7), Color.indigo.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    if let icon = item.systemIcon {
                        Image(systemName: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: width * 0.32, height: height * 0.32)
                            .foregroundColor(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                    }
                }
            }
            
            // 2. 玻璃反光涂层（增加立体质感）
            LinearGradient(
                colors: [Color.white.opacity(0.22), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            // 3. 精致白边
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 2)
        )
    }
}

// MARK: - 背景柔和流体彩带
private struct FluidRainbowBackground: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            
            var path1 = Path()
            path1.move(to: CGPoint(x: 0, y: h * 0.3))
            path1.addCurve(
                to: CGPoint(x: w, y: h * 0.7),
                control1: CGPoint(x: w * 0.3, y: -h * 0.2),
                control2: CGPoint(x: w * 0.7, y: h * 1.2)
            )
            context.stroke(path1, with: .color(.pink.opacity(0.40)), lineWidth: 45)
            
            var path2 = Path()
            path2.move(to: CGPoint(x: 0, y: h * 0.6))
            path2.addCurve(
                to: CGPoint(x: w, y: h * 0.4),
                control1: CGPoint(x: w * 0.4, y: h * 1.1),
                control2: CGPoint(x: w * 0.6, y: -h * 0.1)
            )
            context.stroke(path2, with: .color(.cyan.opacity(0.38)), lineWidth: 40)
            
            var path3 = Path()
            path3.move(to: CGPoint(x: w * 0.2, y: h * 0.5))
            path3.addCurve(
                to: CGPoint(x: w * 0.8, y: h * 0.5),
                control1: CGPoint(x: w * 0.4, y: h * 0.2),
                control2: CGPoint(x: w * 0.6, y: h * 0.8)
            )
            context.stroke(path3, with: .color(.yellow.opacity(0.32)), lineWidth: 35)
        }
    }
}

// MARK: - 预览（完整页面排版效果）
#Preview {
    OrbitingAvatarView()
}
