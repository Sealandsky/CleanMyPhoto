import SwiftUI
import WidgetKit

// MARK: - On This Day Widget Entry View
struct OnThisDayWidgetEntryView: View {
    let entry: OnThisDayEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Group {
            if entry.snapshot == nil {
                // 分支 1：快照不存在 / 跨天失效
                guidanceView
            } else if entry.snapshot?.state == .noPermission {
                // 分支 2：无照片权限
                noPermissionView
            } else if entry.snapshot?.state == .empty || entry.yearIndex == nil {
                // 分支 3：无照片（严格匹配 + 同月兜底都没有）
                guidanceView
            } else if let snapshot = entry.snapshot,
                      let index = entry.yearIndex,
                      index < snapshot.years.count {
                // 分支 4：正常展示某一年
                readyView(snapshot: snapshot, year: snapshot.years[index])
            } else {
                guidanceView
            }
        }
        .widgetURL(deepLinkURL)
        // 双保险：内容视图忽略安全区，渐变底板铺满整个 widget 卡片
        .ignoresSafeArea()
    }

    // MARK: - Deep link
    private var deepLinkURL: URL {
        if let snapshot = entry.snapshot,
           let index = entry.yearIndex,
           index < snapshot.years.count {
            return snapshot.years[index].deepLinkURL
        }
        // 空态 / 无权限：只进 App，不带 year
        return URL(string: "photato://onthisday")!
    }

    // MARK: - Ready
    @ViewBuilder
    private func readyView(snapshot: OnThisDayWidgetSnapshot, year: OnThisDayWidgetSnapshot.YearEntry) -> some View {
        let cover = WidgetSnapshotStore.loadCover(year)
        let isSmall = family == .systemSmall
        // 小尺寸取最多 3 张羽翼展开；中尺寸取最多 5 张错落拼贴
        let collage = WidgetSnapshotStore.loadCollage(year, limit: isSmall ? 3 : 5)

        // 直接铺满整个 widget：不再加外层圆角裁切与描边，避免四周留白。
        // Widget 的圆角由系统容器统一处理，这里让渐变底板延伸到边缘。
        OnThisDayCollageView(
            images: collage.isEmpty ? [cover].compactMap { $0 } : collage,
            year: year.year,
            photoCount: year.photoCount,
            isMonthFallback: year.isMonthFallback,
            compact: isSmall
        )
    }

    // MARK: - Guidance（无照片 / 跨天失效）
    private var guidanceView: some View {
        ZStack {
            OnThisDayVisualConstants.bannerGradient(isDark: isDark)
            VStack(spacing: 8) {
                Image(systemName: "photo.stack")
                    .font(.system(size: family == .systemSmall ? 26 : 30, weight: .medium))
                    .foregroundColor(OnThisDayVisualConstants.primaryText(isDark: isDark).opacity(0.85))
                Text(String(localized: "Open Photato to revisit your memories"))
                    .font(.system(size: family == .systemSmall ? 12 : 14, weight: .semibold, design: .rounded))
                    .foregroundColor(OnThisDayVisualConstants.primaryText(isDark: isDark))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - No Permission
    private var noPermissionView: some View {
        ZStack {
            OnThisDayVisualConstants.bannerGradient(isDark: isDark)
            VStack(spacing: 8) {
                Image(systemName: "lockphoto")
                    .font(.system(size: family == .systemSmall ? 26 : 30, weight: .medium))
                    .foregroundColor(OnThisDayVisualConstants.primaryText(isDark: isDark).opacity(0.85))
                Text(String(localized: "Photo Access Required"))
                    .font(.system(size: family == .systemSmall ? 12 : 14, weight: .semibold, design: .rounded))
                    .foregroundColor(OnThisDayVisualConstants.primaryText(isDark: isDark))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                if family != .systemSmall {
                    Text(String(localized: "Open Photato to enable photo access"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(OnThisDayVisualConstants.secondaryText(isDark: isDark))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Preview
#Preview(as: .systemSmall) {
    OnThisDayWidget()
} timeline: {
    OnThisDayEntry(date: .now, yearIndex: 0, snapshot: nil)
}
