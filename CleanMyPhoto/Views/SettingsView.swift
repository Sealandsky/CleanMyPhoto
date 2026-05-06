//
//  SettingsView.swift
//  CleanMyPhoto
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var membershipManager: MembershipManager
    @EnvironmentObject var statisticsManager: StatisticsManager
    @State private var showMembership = false

    var body: some View {
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
                                Text(String(localized: "CleanMyPhoto"))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text(membershipCardSubtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            Spacer()

                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text(String(localized: membershipManager.isPremiumMember ? "Upgrade" : "Upgrade"))
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

                // 调试选项
                Section(String(localized: "Debug")) {
                    Toggle(isOn: Binding(
                        get: { membershipManager.isDebugPremium },
                        set: { membershipManager.setPremiumMember($0) }
                    )) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                                .frame(width: 30)
                            Text(String(localized: "Premium Member"))
                                .foregroundColor(.primary)
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

                    Link(destination: URL(string: "https://example.com/privacy")!) {
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

                    Link(destination: URL(string: "https://example.com/terms")!) {
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
            .navigationBarTitleDisplayMode(.inline)
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
        } else if membershipManager.remainingTrialDays > 0 {
            return String(localized: "\(membershipManager.remainingTrialDays) days left in trial")
        } else {
            return String(localized: "Free")
        }
    }

    private var membershipCardSubtitle: String {
        if membershipManager.isPremiumMember {
            return membershipStatusText
        } else if membershipManager.remainingTrialDays > 0 {
            return String(localized: "Trial expires in \(membershipManager.remainingTrialDays) days")
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
