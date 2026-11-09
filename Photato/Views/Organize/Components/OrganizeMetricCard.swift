import SwiftUI

// MARK: - 分类配色与图标扩展
extension OrganizeCategory {
    /// 活力年轻时尚色系（对标苹果健康与现代数据仪表盘审美）
    var themeColor: Color {
        switch self {
        case .similar:
            // 热情暖珊瑚橙
            return Color(red: 1.0, green: 0.36, blue: 0.22)
        case .duplicates:
            // 翡翠薄荷绿
            return Color(red: 0.08, green: 0.74, blue: 0.44)
        case .largeFiles:
            // 亮天蓝
            return Color(red: 0.0, green: 0.54, blue: 1.0)
        case .blurry:
            // 暖金琥珀色
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

    /// 分类功能说明微文案（建立扫描价值预期）
    var subtitleText: String {
        switch self {
        case .similar:
            return String(localized: "Burst & Similar · Keep the Best")
        case .duplicates:
            return String(localized: "Exact Copies · Free Space")
        case .largeFiles:
            return String(localized: "Heavy Files · Videos & Live")
        case .blurry:
            return String(localized: "Out of Focus · Smart Detection")
        case .poorFace:
            return String(localized: "Blinking & Poor Expressions")
        case .lowQuality:
            return String(localized: "Low Light · Cluttered Shots")
        case .screenshots:
            return String(localized: "Screenshots · Easy Cleanup")
        case .videos:
            return String(localized: "Large Videos · Quick Trim")
        case .livePhotos:
            return String(localized: "Live Moments · Filter & Keep")
        }
    }
}

// MARK: - 按压弹性按钮样式 (App Store 风格微触感)
struct CardPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - 整理功能分类卡片 (Organize Metric Card)
/// 质感升级微卡片：32×32pt Squircle 徽章底托 + 标题与特征说明微文案 + 待扫描/大数字状态
struct OrganizeMetricCard: View {
    let category: OrganizeCategory
    let count: Int
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
                // 1. 顶部：32×32pt 彩色 Squircle 徽章底托 + 标题 + 说明微文案
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(themeColor.opacity(0.12))
                            .frame(width: 32, height: 32)

                        Image(systemName: category.filledIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(themeColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.localizedText)
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(category.subtitleText)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 8)

                // 2. 底部数据状态行
                if isPending {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(.secondaryLabel))

                        Text(String(localized: "Pending Scan"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.05))
                    )
                } else if isLoading && count == 0 {
                    // 正在扫描中：扫描转子与状态文案
                    HStack(alignment: .center, spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(themeColor)

                        Text(String(localized: "Analyzing..."))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))
                            .lineLimit(1)
                    }
                    .frame(height: 28, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(count.formatted())")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(count > 0 ? .primary : Color(.secondaryLabel))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText())

                        Text(unitDescription)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))
                            .lineLimit(1)

                        if count == 0 {
                            Spacer()
                            Text(String(localized: "Clean"))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 104)
            .background(cardBackground)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(CardPressButtonStyle())
    }

    /// 单位与辅助说明文案
    private var unitDescription: String {
        switch category {
        case .similar, .duplicates, .blurry, .poorFace, .lowQuality:
            return String(localized: "photos")
        case .largeFiles:
            return String(localized: "files")
        case .screenshots:
            return String(localized: "screenshots")
        case .videos:
            return String(localized: "videos")
        case .livePhotos:
            return String(localized: "live photos")
        }
    }

    /// 卡片底板：统一纯白底色，微细描边，配柔和悬浮投影
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.04),
                radius: 6,
                x: 0,
                y: 2
            )
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
                // 顶部标签行：弱化为次级说明
                HStack(spacing: 5) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeColor)
                        .frame(width: 16, height: 16, alignment: .leading)

                    Text(String(localized: "Trash"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(.secondaryLabel))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if trashCount > 0 {
                        Circle()
                            .fill(themeColor)
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer(minLength: 10)

                // 底部数据行：大数字 + 单位紧跟其后（底部基线对齐）
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(trashCount.formatted())")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(trashCount > 0 ? themeColor : Color(.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())

                    Text(String(localized: "Pending Cleanup"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(.secondaryLabel))
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 94)
            .background(cardBackground)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(CardPressButtonStyle())
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.cardBackground)
            .shadow(
                color: Color.black.opacity(0.04),
                radius: 8,
                x: 0,
                y: 3
            )
    }
}
