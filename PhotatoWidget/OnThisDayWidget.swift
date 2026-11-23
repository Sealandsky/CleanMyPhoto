import SwiftUI
import WidgetKit

// MARK: - On This Day Widget
struct OnThisDayWidget: Widget {
    let kind = WidgetSharedContainer.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OnThisDayTimelineProvider()) { entry in
            OnThisDayWidgetEntryView(entry: entry)
                // 容器背景与前景底板用同一套暖色渐变，而不是系统材质：
                // 避免系统在内缩区域 / 亚像素边缘露出白色形成「一圈白」，
                // 也保证 StandBy / iPad 等移除 containerBackground 的场景仍是暖色。
                .containerBackground(for: .widget) {
                    OnThisDayWidgetBackground()
                }
        }
        .configurationDisplayName(String(localized: "On This Day"))
        .description(String(localized: "Relive moments from this day in past years"))
        .supportedFamilies([.systemSmall, .systemMedium])
        // 关闭 iOS 17+ 默认的内容边距，让前景渐变底板延伸到 widget 四条边
        .contentMarginsDisabled()
    }
}

// MARK: - Container Background
/// 与主 App 横幅完全一致的暖色渐变，随深浅色模式切换。
private struct OnThisDayWidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OnThisDayVisualConstants.bannerGradient(isDark: colorScheme == .dark)
    }
}
