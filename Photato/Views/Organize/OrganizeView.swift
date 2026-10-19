import SwiftUI
import Photos

struct OrganizeView: View {
    @Bindable var organizeManager: PhotoOrganizeManager
    @ObservedObject var photoManager: PhotoManager
    @EnvironmentObject var statisticsManager: StatisticsManager
    let onCategorySelect: (OrganizeCategory) -> Void

    /// 系统照片库资源总数
    @State private var totalLibraryCount = 0

    // MARK: - 分类分组定义
    /// 媒体类型：属于格式类型筛选
    private static let mediaTypeCategories: [OrganizeCategory] = [
        .screenshots,
        .videos,
        .livePhotos
    ]

    /// 功能类型：智能清理核心分类，计入可清理照片统计
    private static let functionCategories: [OrganizeCategory] = [
        .similar,
        .duplicates,
        .largeFiles,
        .blurry,
        .poorFace,
        .lowQuality
    ]

    // MARK: - 投影规范
    private static let cardShadowColor = Color.black.opacity(0.06)
    private static let cardShadowRadius: CGFloat = 8
    private static let cardShadowX: CGFloat = 0
    private static let cardShadowY: CGFloat = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. 顶部大卡（原版版式与蓝色渐变设计）
                OrganizeScanCard(
                    organizeManager: organizeManager,
                    totalLibraryCount: totalLibraryCount,
                    junkCount: junkCount,
                    junkPercentage: junkPercentage
                )

                // 2. 历史清理成就横幅（若已释放过空间）
                if statisticsManager.storageSpaceSavedBytes > 0 || statisticsManager.totalDeletedPhotos > 0 {
                    cleanedAccomplishmentBanner
                }

                // 3. 智能清理分类 (2列网格纯白卡片)
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(title: String(localized: "Smart Cleanup"))

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(Self.functionCategories) { category in
                            metricCard(for: category)
                        }
                    }
                }

                // 4. 媒体类型 (2列网格纯白卡片)
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(title: String(localized: "Media Types"))

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(Self.mediaTypeCategories) { category in
                            metricCard(for: category)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Color.pageBackground)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .task {
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            totalLibraryCount = PHAsset.fetchAssets(with: options).count

            if organizeManager.totalGroupCount == 0 && !organizeManager.isAnalyzing {
                await organizeManager.quickAnalysis()
            }
        }
        .onChange(of: organizeManager.isAnalyzing) { oldValue, newValue in
            if oldValue && !newValue && organizeManager.hasCompletedFullScan {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: - 可清理照片数量与占比
    private var junkCount: Int {
        organizeManager.uniqueJunkCount(categories: Self.functionCategories)
    }

    private var junkPercentage: Double {
        guard totalLibraryCount > 0, junkCount > 0 else { return 0 }
        return min(1.0, max(0.03, Double(junkCount) / Double(totalLibraryCount)))
    }

    // MARK: - 分类卡片生成器 (2x2 纯白卡片)
    private func metricCard(for category: OrganizeCategory) -> some View {
        let count = organizeManager.stat(for: category)
        let isCategoryLoading = organizeManager.isCategoryLoading(category)
        let isFunctional = Self.functionCategories.contains(category)
        let isPending = isFunctional && !organizeManager.hasCompletedFullScan && !organizeManager.isAnalyzing

        return OrganizeMetricCard(
            category: category,
            count: count,
            isLoading: isCategoryLoading,
            isPending: isPending
        ) {
            handleCategoryTap(category)
        }
    }

    // MARK: - 统一分类点击逻辑
    private func handleCategoryTap(_ category: OrganizeCategory) {
        let isFunctional = Self.functionCategories.contains(category)
        let isPending = isFunctional && !organizeManager.hasCompletedFullScan && !organizeManager.isAnalyzing

        if isPending {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeInOut(duration: 0.3)) {
                organizeManager.startFullAnalysis()
            }
        } else {
            onCategorySelect(category)
        }
    }

    // MARK: - 分组标题组件
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(Color(.secondaryLabel))
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    // MARK: - 历史清理成就横幅
    private var cleanedAccomplishmentBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 0.16, green: 0.78, blue: 0.24))

            Text(String(localized: "Freed \(statisticsManager.storageSpaceSavedText) · Cleaned \(statisticsManager.totalDeletedPhotos) photos"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.16, green: 0.78, blue: 0.24))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        )
    }
}

// MARK: - 顶部大卡（独立子视图隔离刷新，避免扫描高频进度重绘下方卡片网格）
private struct OrganizeScanCard: View {
    @Bindable var organizeManager: PhotoOrganizeManager
    let totalLibraryCount: Int
    let junkCount: Int
    let junkPercentage: Double

    // MARK: - 投影规范
    private static let cardShadowColor = Color.black.opacity(0.06)
    private static let cardShadowRadius: CGFloat = 8
    private static let cardShadowX: CGFloat = 0
    private static let cardShadowY: CGFloat = 3

    var body: some View {
        Group {
            if organizeManager.isAnalyzing {
                analyzingScanCard
            } else if !organizeManager.hasCompletedFullScan {
                unscannedActionCard
            } else if junkCount == 0 {
                cleanLibraryCard
            } else {
                junkResultsCard
            }
        }
        .animation(.easeInOut(duration: 0.35), value: organizeManager.isAnalyzing)
        .animation(.easeInOut(duration: 0.35), value: organizeManager.hasCompletedFullScan)
    }

    /// 1. 扫描中卡片
    private var analyzingScanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(String(localized: "Scanning..."))
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                scanPillButton(title: String(localized: "Cancel"), icon: "xmark.circle.fill") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    organizeManager.cancelAnalysis()
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text(organizeManager.currentStep.isEmpty
                     ? String(localized: "Scanning...")
                     : organizeManager.currentStep)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)

                ScanProgressBar(progress: organizeManager.analysisProgress)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .background(scanCardBackground)
    }

    /// 2. 未扫描态大卡（引导开始扫描）
    private var unscannedActionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(String(localized: "Smart Analysis"))
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                scanPillButton(title: String(localized: "Start Scan"), icon: "sparkles") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        organizeManager.startFullAnalysis()
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Deep scan for duplicates, similar, and blurry photos"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(String(localized: "Tap to analyze all \(totalLibraryCount) photos"))
                        .font(.system(size: 11, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .background(scanCardBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeInOut(duration: 0.3)) {
                organizeManager.startFullAnalysis()
            }
        }
    }

    /// 3. 扫描后确实为 0 的正面反馈态
    private var cleanLibraryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(.headline, design: .rounded))
                    Text(String(localized: "Library is Clean"))
                        .font(.system(.headline, design: .rounded))
                }
                .foregroundColor(.white)

                Spacer()

                scanPillButton(title: String(localized: "Rescan"), icon: "arrow.clockwise.circle.fill") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        organizeManager.startFullAnalysis()
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 42, height: 42)

                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "No junk photos found"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(String(localized: "Analyzed \(totalLibraryCount) photos · In great shape"))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .background(scanCardBackground)
    }

    /// 4. 有可清理照片态
    private var junkResultsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(String(localized: "Junk Items"))
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                scanPillButton(title: String(localized: "Rescan"), icon: "arrow.clockwise.circle.fill") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        organizeManager.startFullAnalysis()
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 10) {
                percentageRingView

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(junkCount)")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())

                    Text("/")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.2))

                    Text("\(totalLibraryCount.formatted())")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .background(scanCardBackground)
    }

    private var percentageRingView: some View {
        let lineWidth: CGFloat = 3.5

        return ZStack {
            // 背景轨道圆环
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: lineWidth)

            // 百分比进度弧线（带平滑展开动效）
            Circle()
                .trim(from: 0, to: junkPercentage)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.65, dampingFraction: 0.75), value: junkPercentage)
        }
        .frame(width: 24, height: 24)
    }

    private var scanCardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.accentGradient)
            .shadow(
                color: Self.cardShadowColor,
                radius: Self.cardShadowRadius,
                x: Self.cardShadowX,
                y: Self.cardShadowY
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
    }

    /// 样式沿用设置页会员卡右侧的「升级」胶囊按钮
    private func scanPillButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
            )
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 扫描流光胶囊进度条 (Scan Shimmer Progress Bar)
private struct ScanProgressBar: View {
    let progress: Double
    @State private var isShimmering = false

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let currentWidth = max(4, min(totalWidth, totalWidth * CGFloat(progress)))

            ZStack(alignment: .leading) {
                // 1. 底槽轨道
                Capsule()
                    .fill(Color.white.opacity(0.22))

                // 2. 进度填充条
                Capsule()
                    .fill(Color.white)
                    .frame(width: currentWidth)

                // 3. 流光扫光效果 (Shimmer)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 80)
                .offset(x: isShimmering ? totalWidth : -80)
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
        .animation(.easeInOut(duration: 0.25), value: progress)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                isShimmering = true
            }
        }
    }
}

#Preview("Organize Dashboard") {
    let organizeManager = PhotoOrganizeManager()
    let photoManager = PhotoManager()
    let statisticsManager = StatisticsManager()

    OrganizeView(
        organizeManager: organizeManager,
        photoManager: photoManager,
        onCategorySelect: { _ in }
    )
    .environmentObject(photoManager)
    .environmentObject(statisticsManager)
    .environmentObject(MembershipManager())
}
