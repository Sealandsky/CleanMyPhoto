import SwiftUI
import Photos

// MARK: - 整理页顶部核心大卡片 (Organize Hero Card)
/// 对标参考截图 1 顶部「Steps」大卡片：
/// 1. 左上角绿双脚/火花图标 + 标题，右上角胶囊操作入口（重新扫描 / 取消扫描）
/// 2. 大字号核心指标（可清理照片数 + 预计释放空间）
/// 3. 9 根圆角胶囊柱状图（带顶端悬浮黑胶囊气泡和底部类别图标）
struct OrganizeHeroCard: View {
    @Bindable var organizeManager: PhotoOrganizeManager
    let totalLibraryCount: Int
    let junkCount: Int
    let recoverableSizeText: String
    let onStartScan: () -> Void
    let onCancelScan: () -> Void
    let onCategorySelect: (OrganizeCategory) -> Void

    @State private var selectedBarIndex: Int = 0

    // MARK: - 9 大分类定义（6 项清理功能 + 3 项媒体类型）
    private static let allDisplayCategories: [OrganizeCategory] = [
        .similar,
        .duplicates,
        .largeFiles,
        .blurry,
        .poorFace,
        .lowQuality,
        .screenshots,
        .videos,
        .livePhotos
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            if organizeManager.isAnalyzing {
                analyzingContent
            } else if !organizeManager.hasCompletedFullScan {
                unscannedContent
            } else if junkCount == 0 {
                cleanLibraryContent
            } else {
                scannedJunkContent
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(heroCardBackground)
        .onAppear {
            updateDefaultSelectedBar()
        }
        .onChange(of: junkCount) { _, _ in
            updateDefaultSelectedBar()
        }
    }

    // MARK: - 卡片底板
    private var heroCardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white)
            .shadow(
                color: Color.black.opacity(0.04),
                radius: 12,
                x: 0,
                y: 4
            )
    }

    // MARK: - 1. 顶部标题与操作行
    private var headerRow: some View {
        HStack(spacing: 8) {
            // 标志性绿色主题小图标（对应截图中的绿色小图标）
            HStack(spacing: 6) {
                Image(systemName: "sparkles.2")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 0.16, green: 0.78, blue: 0.24))

                Text(String(localized: "Storage Health"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            Spacer()

            // 右侧操作胶囊（重新扫描 / 取消）
            if organizeManager.isAnalyzing {
                pillActionButton(title: String(localized: "Cancel"), icon: "xmark.circle.fill", isDestructive: true) {
                    onCancelScan()
                }
            } else if !organizeManager.hasCompletedFullScan {
                pillActionButton(title: String(localized: "Start Scan"), icon: "sparkles", isAccent: true) {
                    onStartScan()
                }
            } else {
                pillActionButton(title: String(localized: "Rescan"), icon: "arrow.clockwise") {
                    onStartScan()
                }
            }
        }
    }

    // MARK: - 2. 已扫描有可清理照片的主态 (对应截图 1 核心视觉)
    private var scannedJunkContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 大数字指标行（对标 3,680 steps | 4.29 km）
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                // 左侧主指标：可清理照片
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(junkCount.formatted())")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(String(localized: "photos to clean"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                // 右侧副指标：预计释放空间
                if !recoverableSizeText.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recoverableSizeText)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(String(localized: "recoverable"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            // 核心 9 柱圆角胶囊分布图（带顶部深色气泡）
            HeroBarChartView(
                items: chartItems,
                selectedIndex: $selectedBarIndex,
                isAnalyzing: false,
                onSelectBar: { idx in
                    if idx >= 0 && idx < Self.allDisplayCategories.count {
                        let cat = Self.allDisplayCategories[idx]
                        if organizeManager.stat(for: cat) > 0 {
                            onCategorySelect(cat)
                        }
                    }
                }
            )
            .padding(.top, 4)
        }
    }

    // MARK: - 3. 正在扫描中态
    private var analyzingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(organizeManager.analysisProgress * 100))%")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.16, green: 0.78, blue: 0.24))

                    Text(String(localized: "Scanning Progress"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totalLibraryCount.formatted())")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(String(localized: "Total Photos"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // 扫描律动柱状条
            HeroBarChartView(
                items: chartItems,
                selectedIndex: $selectedBarIndex,
                isAnalyzing: true
            )
            .padding(.top, 4)

            // 进度条与当前步骤文字
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: organizeManager.analysisProgress)
                    .tint(Color(red: 0.16, green: 0.78, blue: 0.24))

                Text(organizeManager.currentStep.isEmpty
                     ? String(localized: "Scanning...")
                     : organizeManager.currentStep)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(Color(.secondaryLabel))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 4. 未全量扫描态引导
    private var unscannedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totalLibraryCount.formatted())")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(String(localized: "Photos to Analyze"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "AI Deep"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.16, green: 0.78, blue: 0.24))

                    Text(String(localized: "Smart Scan"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // 静态预览柱
            HeroBarChartView(
                items: previewChartItems,
                selectedIndex: $selectedBarIndex,
                isAnalyzing: false
            )
            .padding(.top, 4)

            Text(String(localized: "Tap Start Scan to deep analyze duplicates, similar and blurry photos."))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(.secondaryLabel))
                .lineLimit(2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onStartScan()
        }
    }

    // MARK: - 5. 全库洁净 0 垃圾状态
    private var cleanLibraryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("100%")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.16, green: 0.78, blue: 0.24))

                    Text(String(localized: "Clean Score"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totalLibraryCount.formatted())")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(String(localized: "Photos Analyzed"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // 平缓温和绿波柱
            HeroBarChartView(
                items: cleanChartItems,
                selectedIndex: $selectedBarIndex,
                isAnalyzing: false
            )
            .padding(.top, 4)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.16, green: 0.78, blue: 0.24))
                Text(String(localized: "Library is in great shape · No junk photos"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(.secondaryLabel))
            }
        }
    }

    // MARK: - 胶囊操作按钮
    private func pillActionButton(
        title: String,
        icon: String,
        isAccent: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(
                isDestructive
                    ? Color(.systemRed)
                    : isAccent
                        ? Color.white
                        : Color.primary
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isAccent
                            ? Color(red: 0.16, green: 0.78, blue: 0.24)
                            : Color(.systemGray6)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据模型转换
    private var chartItems: [HeroBarItem] {
        let maxCount = max(1, Self.allDisplayCategories.map { organizeManager.stat(for: $0) }.max() ?? 1)

        return Self.allDisplayCategories.map { cat in
            let count = organizeManager.stat(for: cat)
            let ratio = CGFloat(count) / CGFloat(maxCount)
            return HeroBarItem(
                id: cat.rawValue,
                icon: cat.filledIcon,
                title: cat.localizedText,
                count: count,
                relativeHeight: max(0.2, ratio),
                tintColor: cat.themeColor
            )
        }
    }

    private var previewChartItems: [HeroBarItem] {
        let sampleRatios: [CGFloat] = [0.35, 0.55, 0.42, 0.78, 0.60, 0.48, 0.38, 0.52, 0.40]
        return Self.allDisplayCategories.enumerated().map { index, cat in
            HeroBarItem(
                id: cat.rawValue,
                icon: cat.filledIcon,
                title: cat.localizedText,
                count: 0,
                relativeHeight: sampleRatios[index % sampleRatios.count],
                tintColor: cat.themeColor
            )
        }
    }

    private var cleanChartItems: [HeroBarItem] {
        let sampleRatios: [CGFloat] = [0.22, 0.26, 0.24, 0.30, 0.28, 0.25, 0.22, 0.24, 0.23]
        return Self.allDisplayCategories.enumerated().map { index, cat in
            HeroBarItem(
                id: cat.rawValue,
                icon: cat.filledIcon,
                title: cat.localizedText,
                count: 0,
                relativeHeight: sampleRatios[index % sampleRatios.count],
                tintColor: cat.themeColor
            )
        }
    }

    /// 自动将气泡选定在数量最多的分类柱上
    private func updateDefaultSelectedBar() {
        let counts = Self.allDisplayCategories.map { organizeManager.stat(for: $0) }
        if let maxIdx = counts.enumerated().max(by: { $0.element < $1.element })?.offset, counts[maxIdx] > 0 {
            selectedBarIndex = maxIdx
        } else {
            selectedBarIndex = 0
        }
    }
}
