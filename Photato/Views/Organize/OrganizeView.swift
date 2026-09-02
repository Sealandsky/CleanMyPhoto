import SwiftUI
import Photos

struct OrganizeView: View {
    @Bindable var organizeManager: PhotoOrganizeManager
    @ObservedObject var photoManager: PhotoManager
    let onCategorySelect: (OrganizeCategory) -> Void

    /// 系统照片库资源总数（扫描卡片的分母展示；惰性 count 查询，开销极小）
    @State private var totalLibraryCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                scanCard

                // 功能类型分组：标题 + 一行两项的紧凑功能卡网格
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Categories"))
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(Color(.systemGray))

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        categoryCards
                    }
                }
            }
            .padding(16)
            // 尾部高度占位：滚动到底时最后一个卡片不被悬浮底栏遮挡
            .padding(.bottom, 74)
        }
        .scrollIndicators(.hidden)  // 隐藏滚动条
        .background(Color(UIColor.systemGroupedBackground))
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

    // MARK: - 废片数量（各分类计数之和，扫描卡大数字的分子）
    private var junkCount: Int {
        OrganizeCategory.allCases.reduce(0) { $0 + organizeManager.stat(for: $1) }
    }

    // MARK: - Scan Card（Figma 597:196：黑色大卡 + 大数字 废片数/总数）
    /// 结构：上行为标题 + 操作胶囊按钮，下行为装饰图标 + 「废片数 / 总数」大数字；
    /// 扫描中替换为进度条 + 取消按钮。三种状态共用同一卡片容器。
    @ViewBuilder
    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 上行：标题 + 操作按钮
            HStack(spacing: 6) {
                Text(scanTitleText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                scanActionButton
            }
            Spacer()
            // 下行：大数字（废片数 / 总数）或扫描进度
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
                .padding(.top, 8)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // 装饰图标：双圆重叠（对齐设计稿 Ellipse 7/8）
                    ZStack {
                        Circle().fill(Color(white: 0.85))
                        Circle().fill(Color.white)
                            .offset(x: 6, y: 2)
                    }
                    .frame(width: 20, height: 20)
                    .padding(.trailing, 8)

                    Text("\(junkCount)")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Text("/")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))

                    Text("\(totalLibraryCount)")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
        // 设计稿：黑色 80% 卡面 + 12pt 圆角；深浅模式下均为深色卡、白字
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
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
            scanPillButton(title: String(localized: "Rescan"), icon: "arrow.clockwise") {
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
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
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

    // MARK: - Category Cards（Figma：一行两项的紧凑功能卡）
    private var categoryCards: some View {
        ForEach(OrganizeCategory.allCases) { category in
            categoryCard(for: category)
        }
    }

    private func categoryCard(for category: OrganizeCategory) -> some View {
        let count = organizeManager.stat(for: category)
        let hasResults = count > 0

        return Button {
            if hasResults {
                onCategorySelect(category)
            } else {
                organizeManager.startFullAnalysis()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white)

                Text(category.localizedText)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(.systemGray))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(organizeManager.isAnalyzing)
        .opacity(organizeManager.isAnalyzing ? 0.5 : 1)
    }
}
