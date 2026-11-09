import SwiftUI
import Photos

// MARK: - Timeline Archive Section View
/// 「时光归档」模块主视图：
/// 1. 分区标题行：左侧「时光归档」，右侧「全部年份 ›」；
/// 2. 年份胶囊横滑栏：高度 32pt，选中深蓝高亮，未选中纯白卡片微描边；
/// 3. 月份卡片横滑区：112×112pt 方正微卡片，精选封面 + 底部渐变防遮挡 + 月份与张数；
/// 4. 骨架屏与空状态支持。
struct TimelineArchiveSectionView: View {
    @ObservedObject var manager: TimelineArchiveManager
    var onMonthSelect: (TimelineMonthItem) -> Void
    var onViewAllYears: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 分区标题栏
            sectionHeader

            // 2. 年份胶囊横滑栏
            if !manager.availableYears.isEmpty {
                yearsScrollRow
            }

            // 3. 月份卡片横滑区 / 骨架屏 / 空状态
            contentArea
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
        .task {
            if !manager.hasLoadedOnce {
                await manager.loadTimeline()
            }
        }
    }

    // MARK: - 1. 分区标题行
    private var sectionHeader: some View {
        HStack(alignment: .center) {
            Text(String(localized: "Timeline Archive"))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if let onViewAllYears {
                Button {
                    onViewAllYears()
                } label: {
                    HStack(spacing: 2) {
                        Text(String(localized: "All Years ›"))
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 2. 年份胶囊横滑栏
    private var yearsScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(manager.availableYears, id: \.self) { year in
                    let isSelected = (manager.selectedYear == year)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task {
                            await manager.selectYear(year)
                        }
                    } label: {
                        Text(yearString(for: year))
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .rounded))
                            .foregroundColor(isSelected ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.accentColor : Color.cardBackground)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 32)
    }

    private func yearString(for year: Int) -> String {
        let currentLang = Locale.current.language.languageCode?.identifier ?? ""
        if currentLang.hasPrefix("zh") {
            return "\(year)年"
        }
        return "\(year)"
    }

    // MARK: - 3. 内容展示区
    @ViewBuilder
    private var contentArea: some View {
        if manager.isLoading && manager.currentMonths.isEmpty {
            skeletonRow
        } else if manager.currentMonths.isEmpty {
            emptyStateView
        } else {
            monthsScrollRow
        }
    }

    // MARK: - 月份卡片横滑区
    private var monthsScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(manager.currentMonths) { item in
                    TimelineMonthCard(item: item)
                        .onTapGesture {
                            onMonthSelect(item)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - 骨架屏占位
    private var skeletonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.cardBackground)
                        .frame(width: 102, height: 136)
                        .shimmering(cornerRadius: 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - 空状态
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28, design: .rounded))
                .foregroundColor(.secondary)
            Text(String(localized: "No photos for this year"))
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 136)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.cardBackground)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Timeline Month Card
/// 单个 102×136pt (3:4 比例) 月份封面微卡片（与二级页日历网格比例完全一致）
private struct TimelineMonthCard: View {
    let item: TimelineMonthItem

    @State private var coverImage: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 1. 封面图
            Group {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
            }
            .frame(width: 102, height: 136)
            .clipped()

            // 2. 底部保护渐变：底部 55% 黑色渐变遮罩
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.4), location: 0.35),
                    .init(color: .black.opacity(0.85), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .allowsHitTesting(false)

            // 3. 底部文字排版（月份加粗 + 照片张数）
            VStack(alignment: .leading, spacing: 1) {
                Text(item.monthName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)

                Text(String(localized: "\(item.photoCount) Photos"))
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 7)
        }
        .frame(width: 102, height: 136)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .onAppear {
            loadCover()
        }
    }

    private func loadCover() {
        guard let asset = item.coverAsset, coverImage == nil else { return }
        let targetSize = CGSize(width: 300, height: 400)
        let key = "timeline_\(item.id)"

        if let cached = PhotoImageCache.shared.get(for: key, targetSize: targetSize, isHighQuality: false) {
            self.coverImage = cached
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { img, info in
            guard let img else { return }
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !isDegraded {
                PhotoImageCache.shared.set(for: key, targetSize: targetSize, isHighQuality: false, image: img)
            }
            self.coverImage = img
        }
    }
}
