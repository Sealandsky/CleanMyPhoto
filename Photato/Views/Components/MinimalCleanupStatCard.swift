import SwiftUI

// MARK: - 设置页极简清理成就卡片 (Minimalist Cleanup Stat Card)
struct MinimalCleanupStatCard: View {
    @ObservedObject var statisticsManager: StatisticsManager
    @ObservedObject var membershipManager: MembershipManager
    let totalLibraryCount: Int
    let onUpgradePro: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // 1. 上半部分：双核心战果并列
            HStack(alignment: .center, spacing: 0) {
                // 左列：已释放空间
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Space Saved"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(.secondaryLabel))

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(statisticsManager.storageSpaceSavedText)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 竖向极细分割线
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 1, height: 36)
                    .padding(.horizontal, 16)

                // 右列：已清理照片
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Cleaned Photos"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(.secondaryLabel))

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(statisticsManager.totalPhotosDeleted.formatted())")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .contentTransition(.numericText())

                        Text(String(localized: "photos"))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 2. 细分界线
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.8)

            // 3. 底部轻量辅助行
            HStack {
                Text(String(format: String(localized: "Total Photos: %@"), totalLibraryCount.formatted()))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(Color(.secondaryLabel))

                Spacer()

                if membershipManager.isPremiumMember {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                        Text(String(localized: "Pro Unlimited"))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                } else {
                    Button(action: onUpgradePro) {
                        HStack(spacing: 3) {
                            Text(String(format: String(localized: "Free quota: %d/%d remaining"), membershipManager.freeDeletionQuotaRemaining, membershipManager.freeDeletionQuotaTotal))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}
