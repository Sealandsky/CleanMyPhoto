

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var membershipManager: MembershipManager
    @EnvironmentObject var statisticsManager: StatisticsManager
    @State private var showMembership = false
    @Environment(GridSettings.self) private var gridSettings

    var body: some View {
        @Bindable var gridSettings = gridSettings
        NavigationView {
            List {
                // 会员卡片（独立展示）
                Section {
                    Button {
                        showMembership = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .opacity(0.85)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "Photato Pro"))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text(membershipCardSubtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            Spacer()

                            if membershipManager.membershipStatus.currentTier != .lifetime {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    Text(String(localized: "Upgrade"))
                                        .font(.subheadline)
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
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0, green: 0.52, blue: 1.0), Color(red: 0, green: 0.72, blue: 1.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                // 使用统计
                Section(String(localized: "Statistics")) {
                    StatRow(icon: "photo.stack",
                            title: String(localized: "Total Photos"),
                            value: statisticsManager.totalPhotosText)

                    StatRow(icon: "trash",
                            title: String(localized: "Deleted Photos"),
                            value: statisticsManager.deletedPhotosText)

                    StatRow(icon: "tray.full",
                            title: String(localized: "In Trash"),
                            value: statisticsManager.trashCountText)

                    StatRow(icon: "externaldrive",
                            title: String(localized: "Space Saved"),
                            value: statisticsManager.storageSpaceSavedText)
                }

                // 显示设置
                Section(String(localized: "Display")) {
                    HStack {
                        Image(systemName: "square.grid.2x2")
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
                            Text("\(gridSettings.columnCount)")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Image(systemName: "rectangle.split.3x1")
                            .frame(width: 30)

                        Text(String(localized: "Photo Ratio"))

                        Spacer()

                        Menu {
                            Button { gridSettings.aspectRatio = 1.0 } label: {
                                Label("1:1", systemImage: "square")
                            }
                            Button { gridSettings.aspectRatio = 3.0 / 4.0 } label: {
                                Label("3:4", systemImage: "rectangle.portrait")
                            }
                        } label: {
                            Text(gridSettings.aspectRatio == 1.0 ? "1:1" : "3:4")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 关于
                Section(String(localized: "About")) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.white)
                            .frame(width: 30)

                        Text(String(localized: "Version"))
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://sealandsky.github.io/privacy/privacy.html")!) {
                        HStack {
                            Image(systemName: "hand.raised")
                                .foregroundColor(.white)
                                .frame(width: 30)

                            Text(String(localized: "Privacy Policy"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Link(destination: URL(string: "https://sealandsky.github.io/privacy/terms-of-use.html")!) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.white)
                                .frame(width: 30)

                            Text(String(localized: "Terms of Use"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .navigationBarTitleDisplayMode(.automatic)
        }
        .fullScreenCover(isPresented: $showMembership) {
            MembershipView(isMandatory: false)
        }
    }

    // MARK: - 计算属性

    private var membershipStatusText: String {
        if membershipManager.isPremiumMember {
            let tier = membershipManager.membershipStatus.currentTier
            switch tier {
            case .monthly:
                return String(localized: "Monthly Member")
            case .yearly:
                return String(localized: "Yearly Member")
            case .lifetime:
                return String(localized: "Lifetime Member")
            case .free:
                return String(localized: "Free")
            }
        } else if membershipManager.remainingTrialDays > 0, let text = membershipManager.remainingTrialText {
            return text
        } else {
            return String(localized: "Free")
        }
    }

    private var membershipCardSubtitle: String {
        if membershipManager.isPremiumMember {
            return membershipStatusText
        } else if membershipManager.remainingTrialDays > 0, let text = membershipManager.remainingTrialText {
            return text
        } else {
            return String(localized: "Subscribe or one-time purchase")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(MembershipManager())
            .environmentObject(StatisticsManager())
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
                .foregroundColor(.white)
                .frame(width: 30)

            Text(title)
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .foregroundColor(.secondary)
        }
    }
}
