import SwiftUI
import Photos

struct OrganizeView: View {
    @Bindable var organizeManager: PhotoOrganizeManager
    @ObservedObject var photoManager: PhotoManager
    let onCategorySelect: (OrganizeCategory) -> Void

    /// 系统照片库资源总数（扫描卡片的分母展示；惰性 count 查询，开销极小）
    @State private var totalLibraryCount = 0

    // MARK: - 分类分组定义
    /// 媒体类型：属于格式类型筛选，不计入废片统计
    private static let mediaTypeCategories: [OrganizeCategory] = [
        .videos,
        .livePhotos
    ]

    /// 功能类型：废片清理功能分类，计入废片统计
    private static let functionCategories: [OrganizeCategory] = [
        .similar,
        .duplicates,
        .screenshots,
        .largeFiles,
        .lowQuality,
        .blurry,
        .poorFace
    ]

    // MARK: - 投影规范（Figma: X:0, Y:3, Blur:6, Spread:0, Color: #000000 6%）
    private static let cardShadowColor = Color.black.opacity(0.06)
    private static let cardShadowRadius: CGFloat = 8
    private static let cardShadowX: CGFloat = 0
    private static let cardShadowY: CGFloat = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                scanCard

                // 功能类型分组：标题 + 一行两项的紧凑功能卡网格
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Categories"))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(.systemGray))

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Self.functionCategories) { category in
                            categoryCard(for: category)
                        }
                    }
                }

                // 媒体类型分组：复用功能类型标题样式 + 一行两项的紧凑功能卡网格
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Media Types"))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(.systemGray))

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Self.mediaTypeCategories) { category in
                            categoryCard(for: category)
                        }
                    }
                }
            }
            .padding(16)
            // 尾部高度占位：滚动到底时最后一个卡片不被悬浮底栏遮挡
            .padding(.bottom, 74)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .scrollIndicators(.hidden)  // 隐藏滚动条
        .task {
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            totalLibraryCount = PHAsset.fetchAssets(with: options).count

            if organizeManager.totalGroupCount == 0 && !organizeManager.isAnalyzing {
                await performInitialScan()
            }
        }
    }

    private func performInitialScan() async {
        await organizeManager.quickAnalysis()
    }

    // MARK: - 废片数量与占比（排除媒体类型：视频和实况照片不属于废片，不计入）
    private var junkCount: Int {
        Self.functionCategories.reduce(0) { $0 + organizeManager.stat(for: $1) }
    }

    private var junkPercentage: Double {
        guard totalLibraryCount > 0, junkCount > 0 else { return 0 }
        return min(1.0, max(0.03, Double(junkCount) / Double(totalLibraryCount)))
    }

    // MARK: - 百分比圆环图标
    private var percentageRingView: some View {
        let lineWidth: CGFloat = 3.5

        return ZStack {
            // 背景轨道圆环
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: lineWidth)

            // 百分比进度弧线（结构恒定，无条件渲染，消除出现时的位移动画）
            Circle()
                .trim(from: 0, to: junkPercentage)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24, height: 24)
    }

    // MARK: - Scan Card（Figma 597:196：黑色大卡 + 大数字 废片数/总数）
    /// 结构：上行为标题 + 操作胶囊按钮，中间 Spacer 撑开，下行为百分比圆环 + 「废片数 / 总数」大数字；
    /// 扫描中替换为进度条 + 取消按钮。卡片固定高度 128pt，数据牢固吸底。
    /// 卡面为深色特例组件（不随浅色主题变化），文字固定白色
    @ViewBuilder
    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 上行：标题 + 操作按钮
            HStack(spacing: 6) {
                Text(scanTitleText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                scanActionButton
            }

            Spacer(minLength: 0)

            // 下行：大数字（废片数 / 总数）或扫描进度（吸附于卡片底部）
            if organizeManager.isAnalyzing {
                VStack(alignment: .leading, spacing: 6) {
                    Text(organizeManager.currentStep.isEmpty
                         ? String(localized: "Scanning...")
                         : organizeManager.currentStep)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)

                    ProgressView(value: organizeManager.analysisProgress)
                        .tint(.blue)
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    // 百分比圆环
                    percentageRingView

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(junkCount)")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        Text("/")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.2))

                        Text("\(totalLibraryCount)")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.2))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        // 黑色 80% 卡面 + 24pt 圆角；深浅模式下均为深色卡、白字
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.8))
                .shadow(
                    color: Self.cardShadowColor,
                    radius: Self.cardShadowRadius,
                    x: Self.cardShadowX,
                    y: Self.cardShadowY
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// 扫描卡标题与操作按钮（按扫描状态切换）
    private var scanTitleText: String {
        if organizeManager.isAnalyzing {
            return String(localized: "Scanning...")
        }
        return organizeManager.hasLoadedInitialData
            ? String(localized: "Junk Items")
            : String(localized: "Start Scan")
    }

    @ViewBuilder
    private var scanActionButton: some View {
        if organizeManager.isAnalyzing {
            scanPillButton(title: String(localized: "Cancel"), icon: "xmark.circle.fill") {
                organizeManager.cancelAnalysis()
            }
        } else if organizeManager.hasLoadedInitialData {
            scanPillButton(title: String(localized: "Rescan"), icon: "arrow.clockwise.circle.fill") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    organizeManager.startFullAnalysis()
                }
            }
        } else {
            scanPillButton(title: String(localized: "Scan"), icon: "magnifyingglass") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    organizeManager.startFullAnalysis()
                }
            }
        }
    }

    private func scanPillButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
            )
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Card（Figma：一行两项的紧凑功能卡）

    private func categoryCard(for category: OrganizeCategory) -> some View {
        let count = organizeManager.stat(for: category)
        let hasResults = count > 0

        return Button {
            if hasResults {
                if !organizeManager.isCategoryLoaded(category) {
                    Task {
                        await organizeManager.loadCategory(category)
                    }
                }
                onCategorySelect(category)
            } else {
                organizeManager.startFullAnalysis()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(width: 24, height: 24, alignment: .center)

                Text(category.localizedText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Text("\(count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(.systemGray))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .shadow(
                        color: Self.cardShadowColor,
                        radius: Self.cardShadowRadius,
                        x: Self.cardShadowX,
                        y: Self.cardShadowY
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(organizeManager.isAnalyzing)
        .opacity(organizeManager.isAnalyzing ? 0.5 : 1)
    }
}
