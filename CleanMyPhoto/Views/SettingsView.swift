//
//  SettingsView.swift
//  CleanMyPhoto
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var membershipManager: MembershipManager
    @State private var showMembership = false

    var body: some View {
        NavigationView {
            List {
                // 会员管理
                Section {
                    Button {
                        showMembership = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "Membership Status"))
                                    .foregroundColor(.primary)

                                Text(membershipStatusText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
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
    }
}
