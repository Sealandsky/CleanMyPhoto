

import SwiftUI
import Photos

struct SettingsView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var membershipManager: MembershipManager
    @EnvironmentObject var statisticsManager: StatisticsManager
    @Environment(PhotoOrganizeManager.self) private var organizeManager: PhotoOrganizeManager?
    var onNavigateToOrganize: (() -> Void)? = nil

    @State private var totalLibraryCount = 0
    @State private var showMembership = false
    @State private var showFeedback = false
    @Environment(GridSettings.self) private var gridSettings

    /// 比例选项的当前显示文案（原比例 / 1:1 / 3:4）
    private var ratioDisplayText: String {
        if gridSettings.isOriginalRatio {
            return String(localized: "Original")
        }
        return gridSettings.aspectRatio == 1.0 ? "1:1" : "3:4"
    }

    var body: some View {
        @Bindable var gridSettings = gridSettings
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 会员卡片（独立展示）
                    membershipCard

                    // 清理成果与存储看板
                    cleanupDashboardCard

                    // 排列方式设置
                    layoutSection(gridSettings: gridSettings)

                    // 关于
                    aboutSection

                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)  // 隐藏滚动条
            .background(Color.pageBackground)
            .tabInlineNavigationTitle(String(localized: "Settings"))
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .task {
                refreshLibraryPhotoCount()
            }
        }
        .fullScreenCover(isPresented: $showMembership) {
            MembershipView(isMandatory: false)
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
    }

    // MARK: - Sections

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundColor(Color(.secondaryLabel))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 6)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var membershipCard: some View {
        Button {
            showMembership = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(.title, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(0.85)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Photato Pro"))
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text(membershipCardSubtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }

                Spacer()

                if membershipManager.membershipStatus.currentTier != .lifetime {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.semibold)
                        Text(String(localized: "Upgrade"))
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
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 16)
            .background(.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var cleanupDashboardCard: some View {
        MinimalCleanupStatCard(
            statisticsManager: statisticsManager,
            membershipManager: membershipManager,
            totalLibraryCount: max(totalLibraryCount, photoManager.totalPhotoCount, statisticsManager.currentPhotoCount),
            onUpgradePro: {
                showMembership = true
            }
        )
    }

    private func layoutSection(gridSettings: GridSettings) -> some View {
        sectionCard(title: String(localized: "Layout")) {
            HStack(spacing: 12) {
                SettingsIconView(systemName: "square.grid.2x2.fill", color: .cyan)

                Text(String(localized: "Grid Layout"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                Menu {
                    Button { gridSettings.columnCount = 2 } label: {
                        Label("2", systemImage: "square.grid.2x2.fill")
                    }
                    Button { gridSettings.columnCount = 3 } label: {
                        Label("3", systemImage: "square.grid.3x2.fill")
                    }
                    Button { gridSettings.columnCount = 4 } label: {
                        Label("4", systemImage: "square.grid.3x2.fill")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(gridSettings.columnCount)")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)

            HStack(spacing: 12) {
                SettingsIconView(systemName: "aspectratio.fill", color: .orange)

                Text(String(localized: "Photo Ratio"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                Menu {
                    Button { gridSettings.isOriginalRatio = true } label: {
                        Label(String(localized: "Original"), systemImage: "rectangle.on.rectangle")
                    }
                    Button {
                        gridSettings.isOriginalRatio = false
                        gridSettings.aspectRatio = 1.0
                    } label: {
                        Label("1:1", systemImage: "square")
                    }
                    Button {
                        gridSettings.isOriginalRatio = false
                        gridSettings.aspectRatio = 3.0 / 4.0
                    } label: {
                        Label("3:4", systemImage: "rectangle.portrait")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(ratioDisplayText)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
        }
    }

    private var aboutSection: some View {
        sectionCard(title: String(localized: "About")) {
            Button {
                showFeedback = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIconView(systemName: "envelope.fill", color: .pink)

                    Text(String(localized: "Send Feedback"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                SettingsIconView(systemName: "info.circle.fill", color: .gray)

                Text(String(localized: "Version"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Text(appVersion)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)

            Link(destination: ReviewPromptManager.appStoreReviewURL) {
                HStack(spacing: 12) {
                    SettingsIconView(systemName: "star.fill", color: .yellow)

                    Text(String(localized: "Rate Photato"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Link(destination: privacyPolicyURL) {
                HStack(spacing: 12) {
                    SettingsIconView(systemName: "hand.raised.fill", color: .green)

                    Text(String(localized: "Privacy Policy"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Link(destination: URL(string: "https://sealandsky.github.io/privacy/terms-of-use.html")!) {
                HStack(spacing: 12) {
                    SettingsIconView(systemName: "doc.text.fill", color: .blue)

                    Text(String(localized: "Terms of Use"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    #if DEBUG
    private var debugSection: some View {
        sectionCard(title: "Debug") {
            Toggle(isOn: $membershipManager.isDebugPremium) {
                HStack(spacing: 12) {
                    SettingsIconView(systemName: "crown.fill", color: .yellow)
                    Text("Simulate Pro Member")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)

            Button {
                membershipManager.resetFreeQuotaForTesting()
            } label: {
                HStack(spacing: 12) {
                    SettingsIconView(systemName: "arrow.counterclockwise.circle.fill", color: .blue)
                    Text("Reset Free Quota (100 left)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.blue)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)

            Button {
                membershipManager.exhaustFreeQuotaForTesting()
            } label: {
                HStack(spacing: 12) {
                    SettingsIconView(systemName: "xmark.circle.fill", color: .red)
                    Text("Exhaust Free Quota (0 left)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)

            Button {
                photoManager.lastCleanupResult = CleanupResult(deletedCount: 24, freedBytes: 256_000_000)
            } label: {
                HStack(spacing: 12) {
                    SettingsIconView(systemName: "sparkles", color: .purple)
                    Text("Test Cleanup Result Page")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
        }
    }
    #endif

    // MARK: - 计算属性

    /// 总照片数展示：复用系统相册资源总数（单位为“张”）
    private var totalPhotosDisplayText: String {
        let count = max(totalLibraryCount, photoManager.totalPhotoCount, statisticsManager.currentPhotoCount)
        if count > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            let formatted = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
            return String(localized: "Photo Count Unit \(formatted)")
        }
        return statisticsManager.totalPhotosText
    }

    /// 查询系统相册资源总数（与清理页卡片口径一致：无隐藏照片的总资产数）
    private func refreshLibraryPhotoCount() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            totalLibraryCount = PHAsset.fetchAssets(with: options).count
            if totalLibraryCount > 0 && statisticsManager.currentPhotoCount != totalLibraryCount {
                statisticsManager.currentPhotoCount = totalLibraryCount
            }
        }
    }

    // MARK: - 可清理照片行
    @ViewBuilder
    private var cleanablePhotosRow: some View {
        Button {
            onNavigateToOrganize?()
        } label: {
            HStack(spacing: 12) {
                SettingsIconView(systemName: "sparkles", color: .purple)

                Text(String(localized: "Cleanable Photos"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                if let manager = organizeManager, manager.hasCompletedFullScan {
                    HStack(spacing: 4) {
                        Text(cleanablePhotosDisplayText)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundColor(Color(uiColor: .secondaryLabel))
                    }
                } else if let manager = organizeManager, manager.isAnalyzing {
                    HStack(spacing: 4) {
                        Text(String(localized: "Scanning..."))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.blue)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundColor(Color(uiColor: .secondaryLabel))
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(String(localized: "To Scan"))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.blue)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundColor(Color(uiColor: .secondaryLabel))
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 可清理照片显示文案（复用 PhotoOrganizeManager 数据，单位为“张”）
    private var cleanablePhotosDisplayText: String {
        guard let manager = organizeManager else {
            return String(localized: "To Scan")
        }
        let count = manager.cleanablePhotoCount
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return String(localized: "Photo Count Unit \(formatted)")
    }

    private var membershipCardSubtitle: String {
        if membershipManager.isPremiumMember {
            return String(localized: "Pro Activated")
        } else {
            return String(localized: "Unlock Permanent Deletion")
        }
    }

    /// 免费删除额度显示（复用 MembershipManager.quotaDisplayText）：
    /// 会员「无限」；免费显示剩余/总额；用尽提示升级
    private var quotaDisplayText: String {
        membershipManager.quotaDisplayText
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// 隐私政策按设备语言跳转对应版本
    private var privacyPolicyURL: URL {
        let isChinese = Locale.current.language.languageCode?.identifier == "zh"
        return URL(string: isChinese
            ? "https://sealandsky.github.io/privacy/privacy-policy-zh.html"
            : "https://sealandsky.github.io/privacy/privacy-policy.html")!
    }
}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(PhotoManager())
            .environmentObject(MembershipManager())
            .environmentObject(StatisticsManager())
            .environment(GridSettings())
    }
}

// MARK: - Stat Row Component
struct StatRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconView(systemName: icon, color: iconColor)

            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }
}

// MARK: - Settings Icon Component (Optical Balanced)
struct SettingsIconView: View {
    let systemName: String
    let color: Color

    /// 针对不同外形、宽高比与实心度的 SF Symbol 进行光学尺寸微调，
    /// 确保视觉面积、高度与密度在 28x28 槽位中完全均衡统一。
    private var opticalPointSize: CGFloat {
        switch systemName {
        case "sparkles":
            return 25 // 镂空细线条符号：提升字阶增加视觉占比
        case "internaldrive.fill":
            return 23.5 // 扁平横向符号：增大字阶拉高视觉纵深
        case "hand.raised.fill", "doc.text.fill":
            return 22.5 // 纵向偏窄符号：微调放大增强视觉体量
        case "checkmark.seal.fill", "info.circle.fill", "square.grid.2x2.fill":
            return 20 // 密集圆/方实心饱满符号：微降字阶避免压迫感
        default:
            return 21 // 标准平衡符号（photo.stack.fill, trash.fill, star.fill, aspectratio.fill, envelope.fill 等）
        }
    }

    private var opticalWeight: Font.Weight {
        switch systemName {
        case "sparkles":
            return .bold // 细线符号加粗线宽，匹配实心 fill 的质感与墨量
        default:
            return .semibold
        }
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: opticalPointSize, weight: opticalWeight, design: .rounded))
            .foregroundColor(color)
            .frame(width: 28, height: 28, alignment: .center)
    }
}
