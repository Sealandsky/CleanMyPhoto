import SwiftUI

// MARK: - 视觉微图表类型
enum OrganizeMetricVisualType {
    case gauge(progress: Double)
    case barSparkline(peakIndex: Int)
    case waveSparkline
}

// MARK: - 分类配色与微图表映射扩展
extension OrganizeCategory {
    /// 活力年轻时尚色系（对标苹果健康与现代数据仪表盘审美）
    var themeColor: Color {
        switch self {
        case .similar:
            // 热情暖珊瑚橙（Calories 风格）
            return Color(red: 1.0, green: 0.36, blue: 0.22)
        case .duplicates:
            // 翡翠薄荷绿（Weight 风格）
            return Color(red: 0.08, green: 0.74, blue: 0.44)
        case .largeFiles:
            // 亮天蓝（Water 风格）
            return Color(red: 0.0, green: 0.54, blue: 1.0)
        case .blurry:
            // 暖金琥珀色（Sleep 风格）
            return Color(red: 1.0, green: 0.64, blue: 0.0)
        case .poorFace:
            // 魅惑紫罗兰
            return Color(red: 0.62, green: 0.35, blue: 0.96)
        case .lowQuality:
            // 蜜柑橙红
            return Color(red: 1.0, green: 0.48, blue: 0.16)
        case .screenshots:
            // 电气青绿
            return Color(red: 0.04, green: 0.72, blue: 0.82)
        case .videos:
            // 极光靛蓝
            return Color(red: 0.38, green: 0.38, blue: 0.94)
        case .livePhotos:
            // 霓虹热粉
            return Color(red: 0.96, green: 0.28, blue: 0.58)
        }
    }

    /// 高权重实心图标
    var filledIcon: String {
        switch self {
        case .similar:
            return "photo.stack.fill"
        case .duplicates:
            return "doc.on.doc.fill"
        case .largeFiles:
            return "externaldrive.fill"
        case .blurry:
            return "water.waves"
        case .poorFace:
            return "face.dashed"
        case .lowQuality:
            return "exclamationmark.triangle.fill"
        case .screenshots:
            return "camera.viewfinder"
        case .videos:
            return "video.fill"
        case .livePhotos:
            return "livephoto"
        }
    }

    /// 对应参考截图的三大微图表风格映射
    var visualType: OrganizeMetricVisualType {
        switch self {
        case .similar:
            // 环形刻度进度圈（如 Calories）
            return .gauge(progress: 0.68)
        case .duplicates:
            // 贝塞尔波形曲线（如 Weight）
            return .waveSparkline
        case .largeFiles:
            // 环形刻度进度圈（如 Water）
            return .gauge(progress: 0.54)
        case .blurry:
            // 垂直迷你条形图（如 Sleep）
            return .barSparkline(peakIndex: 3)
        case .poorFace:
            // 贝塞尔波形曲线
            return .waveSparkline
        case .lowQuality:
            // 垂直迷你条形图
            return .barSparkline(peakIndex: 2)
        case .screenshots:
            // 贝塞尔波形曲线
            return .waveSparkline
        case .videos:
            // 环形刻度进度圈
            return .gauge(progress: 0.42)
        case .livePhotos:
            // 垂直迷你条形图
            return .barSparkline(peakIndex: 3)
        }
    }
}

// MARK: - 按压弹性按钮样式
struct CardPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - 整理功能分类卡片 (Organize Metric Card)
/// 参考截图 2x2 网格设计：大数字 + 类别图标 + 专属色彩洗浅底面 + 右侧微图表
struct OrganizeMetricCard: View {
    let category: OrganizeCategory
    let count: Int
    let fileSizeText: String?
    let isLoading: Bool
    let isPending: Bool
    let action: () -> Void

    private var themeColor: Color {
        category.themeColor
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // 1. 顶部行：图标 + 标题 + 加载/待扫描状态
                HStack(spacing: 6) {
                    Image(systemName: category.filledIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeColor)
                        .frame(width: 20, height: 20, alignment: .leading)

                    Text(category.localizedText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isLoading && count == 0 {
                        ProgressView()
                            .controlSize(.mini)
                    } else if isPending {
                        Text(String(localized: "Pending Scan"))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }

                Spacer(minLength: 10)

                // 2. 底部数据行：大数字 + 描述单位在左，微图表在右
                HStack(alignment: .bottom, spacing: 8) {
                    // 大字号指标数值与单位
                    VStack(alignment: .leading, spacing: 1) {
                        if isPending {
                            Text("—")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(Color(.secondaryLabel))
                        } else if let fileSize = fileSizeText, !fileSize.isEmpty {
                            Text(fileSize)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else {
                            Text("\(count.formatted())")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(count > 0 ? .primary : Color(.secondaryLabel))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }

                        Text(unitDescription)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    // 右侧个性化微图表
                    microChart
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(cardBackground)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(CardPressButtonStyle())
    }

    /// 单位与辅助说明文案
    private var unitDescription: String {
        if isPending {
            return String(localized: "Tap to Scan")
        }
        switch category {
        case .similar:
            return String(localized: "photos")
        case .duplicates:
            return String(localized: "photos")
        case .largeFiles:
            return count > 0 ? String(localized: "\(count) files") : String(localized: "files")
        case .blurry:
            return String(localized: "photos")
        case .poorFace:
            return String(localized: "photos")
        case .lowQuality:
            return String(localized: "photos")
        case .screenshots:
            return String(localized: "screenshots")
        case .videos:
            return String(localized: "videos")
        case .livePhotos:
            return String(localized: "live photos")
        }
    }

    /// 卡片底板：统一纯白底色，无背景色水洗，无描边，配柔和悬浮投影
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white)
            .shadow(
                color: Color.black.opacity(0.04),
                radius: 8,
                x: 0,
                y: 3
            )
    }

    /// 微图表选择器
    @ViewBuilder
    private var microChart: some View {
        switch category.visualType {
        case .gauge(let baseProgress):
            let p = count > 0 ? min(1.0, max(0.2, baseProgress)) : 0.08
            CircularGaugeView(progress: p, color: themeColor, lineWidth: 4.5, size: 38)

        case .barSparkline(let peakIndex):
            MiniBarSparklineView(color: themeColor, peakIndex: peakIndex, size: CGSize(width: 38, height: 28))

        case .waveSparkline:
            MiniWaveSparklineView(color: themeColor, size: CGSize(width: 42, height: 26))
        }
    }
}

// MARK: - 废纸篓快捷入口卡片 (Trash Metric Card)
/// 在媒体类型网格中补齐第 4 项对称网格，直接联动已移入待删除的废片数
struct TrashMetricCard: View {
    let trashCount: Int
    let action: () -> Void

    private let themeColor = Color(red: 0.94, green: 0.28, blue: 0.28)

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部行
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeColor)
                        .frame(width: 20, height: 20, alignment: .leading)

                    Text(String(localized: "Trash"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if trashCount > 0 {
                        Circle()
                            .fill(themeColor)
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer(minLength: 10)

                // 底部数据行
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(trashCount.formatted())")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(trashCount > 0 ? themeColor : Color(.secondaryLabel))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(String(localized: "Pending Cleanup"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    CircularGaugeView(
                        progress: trashCount > 0 ? 0.75 : 0.08,
                        color: themeColor,
                        lineWidth: 4.5,
                        size: 38
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(cardBackground)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(CardPressButtonStyle())
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white)
            .shadow(
                color: Color.black.opacity(0.04),
                radius: 8,
                x: 0,
                y: 3
            )
    }
}
