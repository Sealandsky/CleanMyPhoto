import SwiftUI
import Combine

// MARK: - On This Day Section View
/// 「过去的今天」横滑卡片区组件：
/// - 置顶于「相册」页（AlbumListView）上方；
/// - 3.15:1 比例横幅卡片，最外层统一大圆角裁切（cornerRadius 22）；
/// - 暖色底卡：浅色模式柔和米暖渐变（#EFE8DF -> #DED6CB），深色模式深暖炭灰（#242220 -> #1A1918）；
/// - 图层顺序：文字置于照片层下方（底板 -> 固定居中文字 -> 横滑错落照片）；
/// - 错落大照片四周等宽 3.5pt 纯白细边框，无厚下巴留白，多层差速视差横滑；
/// - 纯数字翻转：中央年份与照片张数仅变动数字走 .contentTransition(.numericText()) 垂直翻转；
/// - 下方胶囊型页码指示器，支持点按切页与落定触觉反馈。
struct OnThisDaySectionView: View {
    @ObservedObject var manager: OnThisDayManager
    var onSelectYear: (OnThisDayYearGroup) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var activeGroupID: String?
    @State private var animatedYear: Int = 0
    @State private var animatedCount: Int = 0
    @State private var scrollOffsetX: CGFloat = 0

    var body: some View {
        if !manager.yearGroups.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                bannerCarouselView
                dotsIndicatorView
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .onAppear {
                syncActiveGroupIfNeeded()
            }
            .onChange(of: manager.yearGroups) { _, _ in
                syncActiveGroupIfNeeded()
            }
            .onChange(of: activeGroupID) { oldValue, newValue in
                handleActiveGroupChange(from: oldValue, to: newValue)
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(manager.isMonthFallback ? String(localized: "Past Month Highlights") : String(localized: "On This Day"))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Text(currentDateText)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(Color(.secondaryLabel))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 3.15:1 Banner Carousel
    private var bannerCarouselView: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let bannerHeight = min(126, max(114, containerWidth / 3.15))

            ZStack {
                // 1. 底层：卡片底板（暖色底，浅色米暖渐变，深色深暖炭灰）
                bannerBackground

                // 2. 底层文字（位于照片层下方）：固定居中，仅数字垂直翻转
                centerOverlay(containerHeight: bannerHeight)

                // 3. 上层：横向翻页滚动大照片（单张照片完整不裁切，滑过中央文字上方）
                pagingScrollView(containerWidth: containerWidth, bannerHeight: bannerHeight)
            }
            .frame(width: containerWidth, height: bannerHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 14, x: 0, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(String(localized: "Double tap to view photos from this day"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    advancePage(step: 1)
                case .decrement:
                    advancePage(step: -1)
                @unknown default:
                    break
                }
            }
        }
        .aspectRatio(3.15, contentMode: .fit)
        .padding(.horizontal, 16)
    }

    // MARK: - Banner Background
    private var bannerBackground: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.141, green: 0.133, blue: 0.125),
                        Color(red: 0.102, green: 0.098, blue: 0.094)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.937, green: 0.910, blue: 0.875),
                        Color(red: 0.871, green: 0.839, blue: 0.796)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - Center Overlay (底层文字层：印在卡片底板中央，位于照片层下方)
    private func centerOverlay(containerHeight: CGFloat) -> some View {
        VStack(spacing: 3) {
            // 年份行：例如 "2025" 翻转，"年" 固定不动
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: "\(animatedYear)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12))
                    .contentTransition(.numericText())

                let yearSuffix = String(localized: "year_suffix", defaultValue: "")
                if !yearSuffix.isEmpty {
                    Text(yearSuffix)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12))
                }
            }

            // 照片张数行：例如 "12" 翻转，" 张照片" / " Photos" 固定不动
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: "\(animatedCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? Color(red: 0.60, green: 0.60, blue: 0.62) : Color(red: 0.55, green: 0.55, blue: 0.57))
                    .contentTransition(.numericText())

                Text(String(localized: "photos_count_suffix", defaultValue: " Photos"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? Color(red: 0.60, green: 0.60, blue: 0.62) : Color(red: 0.55, green: 0.55, blue: 0.57))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Paging Scroll View (照片横滑层：位于文字上层，照片滑过文字上方)
    private func pagingScrollView(containerWidth: CGFloat, bannerHeight: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(manager.yearGroups.enumerated()), id: \.element.id) { index, group in
                    OnThisDayYearPageView(
                        group: group,
                        pageIndex: index,
                        containerWidth: containerWidth,
                        containerHeight: bannerHeight,
                        scrollOffsetX: scrollOffsetX,
                        reduceMotion: reduceMotion
                    )
                    .frame(width: containerWidth, height: bannerHeight)
                    .id(group.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelectYear(group)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $activeGroupID)
        .scrollClipDisabled()
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x
        } action: { _, newOffset in
            scrollOffsetX = newOffset
        }
    }

    // MARK: - Dots Indicator
    @ViewBuilder
    private var dotsIndicatorView: some View {
        if manager.yearGroups.count > 1 {
            HStack(spacing: 6) {
                ForEach(manager.yearGroups) { group in
                    let isActive = (group.id == activeGroupID)
                    Capsule()
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.28))
                        .frame(width: isActive ? 16 : 6, height: 6)
                        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isActive)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                activeGroupID = group.id
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 9)
            .padding(.bottom, 2)
        }
    }

    // MARK: - State Helpers
    private func syncActiveGroupIfNeeded() {
        guard !manager.yearGroups.isEmpty else { return }
        if activeGroupID == nil || !manager.yearGroups.contains(where: { $0.id == activeGroupID }) {
            if let first = manager.yearGroups.first {
                activeGroupID = first.id
                animatedYear = first.year
                animatedCount = first.photoCount
            }
        }
    }

    private func handleActiveGroupChange(from oldValue: String?, to newValue: String?) {
        guard let newValue, oldValue != newValue else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        if let target = manager.yearGroups.first(where: { $0.id == newValue }) {
            if reduceMotion {
                animatedYear = target.year
                animatedCount = target.photoCount
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    animatedYear = target.year
                    animatedCount = target.photoCount
                }
            }
        }
    }

    private func advancePage(step: Int) {
        guard let current = activeGroupID,
              let currentIndex = manager.yearGroups.firstIndex(where: { $0.id == current }) else {
            return
        }
        let nextIndex = min(max(0, currentIndex + step), manager.yearGroups.count - 1)
        if nextIndex != currentIndex {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                activeGroupID = manager.yearGroups[nextIndex].id
            }
        }
    }

    // MARK: - Date & Accessibility Helpers
    private var currentDateText: String {
        let now = Date()
        if manager.isMonthFallback {
            return now.formatted(.dateTime.month())
        } else {
            return now.formatted(.dateTime.month().day())
        }
    }

    private var accessibilitySummary: String {
        let prefix = manager.isMonthFallback ? String(localized: "Past Month Highlights") : String(localized: "On This Day")
        let yearStr = "\(animatedYear)"
        let countStr = String(localized: "\(animatedCount) Photos")
        return "\(prefix), \(yearStr), \(countStr)"
    }
}
