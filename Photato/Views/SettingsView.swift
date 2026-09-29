

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

                    // 使用统计
                    statisticsSection

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
    }

    // MARK: - Sections

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Color(.systemGray))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        .foregroundColor(.white.opacity(0.7))
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var statisticsSection: some View {
        sectionCard(title: String(localized: "Statistics")) {
            StatRow(icon: "checkmark.seal",
                    title: String(localized: "Free Deletion Quota"),
                    value: quotaDisplayText)

            Divider().padding(.leading, 54)

            StatRow(icon: "square.on.square",
                    title: String(localized: "Total Photos"),
                    value: totalPhotosDisplayText)

            Divider().padding(.leading, 54)

            cleanablePhotosRow

            Divider().padding(.leading, 54)

            StatRow(icon: "trash",
                    title: String(localized: "Deleted Photos"),
                    value: statisticsManager.deletedPhotosText)

            Divider().padding(.leading, 54)

            StatRow(icon: "externaldrive",
                    title: String(localized: "Space Saved"),
                    value: statisticsManager.storageSpaceSavedText)
        }
    }

    private func layoutSection(gridSettings: GridSettings) -> some View {
        sectionCard(title: String(localized: "Layout")) {
            HStack {
                Image(systemName: "square.grid.2x2")
                    .foregroundColor(.blue)
                    .frame(width: 30)

                Text(String(localized: "Grid Layout"))

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
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)

            Divider().padding(.leading, 54)

            HStack {
                Image(systemName: "rectangle.split.3x1")
                    .foregroundColor(.blue)
                    .frame(width: 30)

                Text(String(localized: "Photo Ratio"))

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
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
    }

    private var aboutSection: some View {
        sectionCard(title: String(localized: "About")) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .frame(width: 30)

                Text(String(localized: "Version"))
                Spacer()
                Text(appVersion)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)

            Divider().padding(.leading, 54)

            Link(destination: ReviewPromptManager.appStoreReviewURL) {
                HStack {
                    Image(systemName: "star")
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    Text(String(localized: "Rate Photato"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .foregroundColor(.primary)

            Divider().padding(.leading, 54)

            Link(destination: privacyPolicyURL) {
                HStack {
                    Image(systemName: "hand.raised")
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    Text(String(localized: "Privacy Policy"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .foregroundColor(.primary)

            Divider().padding(.leading, 54)

            Link(destination: URL(string: "https://sealandsky.github.io/privacy/terms-of-use.html")!) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    Text(String(localized: "Terms of Use"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .foregroundColor(.primary)
        }
    }

    #if DEBUG
    private var debugSection: some View {
        sectionCard(title: "Debug") {
            Toggle("Simulate Pro Member", isOn: $membershipManager.isDebugPremium)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)

            Divider().padding(.leading, 16)

            Button {
                membershipManager.resetFreeQuotaForTesting()
            } label: {
                Text("Reset Free Quota (100 left)")
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)

            Divider().padding(.leading, 16)

            Button {
                membershipManager.exhaustFreeQuotaForTesting()
            } label: {
                Text("Exhaust Free Quota (0 left)")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
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
            HStack {
                Image(systemName: "eraser")
                    .foregroundColor(.blue)
                    .frame(width: 30)

                Text(String(localized: "Cleanable Photos"))
                    .foregroundColor(.primary)

                Spacer()

                if let manager = organizeManager, manager.hasCompletedFullScan {
                    HStack(spacing: 4) {
                        Text(cleanablePhotosDisplayText)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                } else if let manager = organizeManager, manager.isAnalyzing {
                    HStack(spacing: 4) {
                        Text(String(localized: "Scanning..."))
                            .foregroundColor(.blue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.blue)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(String(localized: "To Scan"))
                            .foregroundColor(.blue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
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
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 30)

            Text(title)
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }
}
