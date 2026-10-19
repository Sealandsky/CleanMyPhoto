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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. 顶部核心数据仪表盘大卡片 (参考 Steps 卡片设计)
                OrganizeHeroCard(
                    organizeManager: organizeManager,
                    totalLibraryCount: totalLibraryCount,
                    junkCount: junkCount,
                    recoverableSizeText: recoverableSizeText,
                    onStartScan: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            organizeManager.startFullAnalysis()
                        }
                    },
                    onCancelScan: {
                        organizeManager.cancelAnalysis()
                    },
                    onCategorySelect: { category in
                        handleCategoryTap(category)
                    }
                )

                // 2. 历史清理成就横幅（若已释放过空间）
                if statisticsManager.storageSpaceSavedBytes > 0 || statisticsManager.totalDeletedPhotos > 0 {
                    cleanedAccomplishmentBanner
                }

                // 3. 智能清理分类 (2x2 网格，对标 Calories / Water / Sleep / Weight)
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(
                        title: String(localized: "Smart Cleanup"),
                        badge: String(localized: "\(Self.functionCategories.count) Categories")
                    )

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

                // 4. 媒体类型与回收站 (2x2 网格，补全四格对称)
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(
                        title: String(localized: "Media Types"),
                        badge: String(localized: "4 Items")
                    )

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        // 屏幕快照
                        metricCard(for: .screenshots)
                        // 视频资源
                        metricCard(for: .videos)
                        // 实况照片
                        metricCard(for: .livePhotos)
                        // 待处理废纸篓入口
                        TrashMetricCard(
                            trashCount: photoManager.pendingDeletionIDs.count
                        ) {
                            photoManager.showTrash = true
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
    }

    // MARK: - 分类卡片生成器
    private func metricCard(for category: OrganizeCategory) -> some View {
        let count = organizeManager.stat(for: category)
        let isCategoryLoading = organizeManager.isCategoryLoading(category)
        let isFunctional = Self.functionCategories.contains(category)
        let isPending = isFunctional && !organizeManager.hasCompletedFullScan && !organizeManager.isAnalyzing

        var fileSizeText: String? = nil
        if category == .largeFiles {
            let size = organizeManager.scanResults[.largeFiles]?.first?.potentialSpaceSaved ?? 0
            if size > 0 {
                fileSizeText = ByteFormatter.format(size)
            }
        }

        return OrganizeMetricCard(
            category: category,
            count: count,
            fileSizeText: fileSizeText,
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

    // MARK: - 可清理照片数量与空间估算
    private var junkCount: Int {
        organizeManager.uniqueJunkCount(categories: Self.functionCategories)
    }

    /// 预计可释放空间：结合大文件实际体积与其余垃圾照片均值估算
    private var recoverableSizeText: String {
        let largeFileSize = organizeManager.scanResults[.largeFiles]?.first?.potentialSpaceSaved ?? 0
        let largeFileCount = organizeManager.stat(for: .largeFiles)
        let otherJunkCount = max(0, junkCount - largeFileCount)
        let estimatedOtherBytes = Int64(otherJunkCount) * 3_200_000 // 默认每张估约 3.2MB
        let totalBytes = largeFileSize + estimatedOtherBytes

        guard totalBytes > 0 else { return "" }
        return ByteFormatter.format(totalBytes)
    }

    // MARK: - 分组标题组件
    private func sectionHeader(title: String, badge: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Color(.secondaryLabel))

            Spacer()

            Text(badge)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Color(.tertiaryLabel))
        }
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

