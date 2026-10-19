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
/// 纯白卡片：图标 + 标题 + 大数字后紧跟单位（底部基线对齐），简约优雅
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

                // 2. 底部数据行：大数字 + 跟在后面的单位（底部基线对齐）
                if isPending {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("—")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))

                        Text(String(localized: "Pending Scan"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(.tertiaryLabel))
                            .lineLimit(1)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(count.formatted())")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(count > 0 ? .primary : Color(.secondaryLabel))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText(value: Double(count)))
                            .animation(.snappy(duration: 0.35), value: count)

                        Text(unitDescription)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))
                            .lineLimit(1)
                    }
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

    /// 卡片底板：统一纯白底色，无描边，配柔和悬浮投影
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white)
            .shadow(
                color: Color.black.opacity(0.04),
                radius: 8,
                x: 0,
                y: 3
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

                // 底部数据行：大数字 + 单位紧跟其后（底部基线对齐）
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(trashCount.formatted())")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(trashCount > 0 ? themeColor : Color(.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText(value: Double(trashCount)))
                        .animation(.snappy(duration: 0.35), value: trashCount)

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
            .fill(Color.white)
            .shadow(
                color: Color.black.opacity(0.04),
                radius: 8,
                x: 0,
                y: 3
            )
    }
}
