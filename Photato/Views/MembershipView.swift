

import SwiftUI

struct MembershipView: View {
    @EnvironmentObject private var membershipManager: MembershipManager
    @AppStorage("hasShownMembership") private var hasShownMembership: Bool = false
    @Environment(\.dismiss) private var dismiss

    let isMandatory: Bool

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                scrollView
            }

            if !isMandatory {
                closeButton
            }

            if membershipManager.isLoadingPurchase {
                loadingOverlay
            }
        }
        .navigationBarHidden(true)
        .alert(String(localized: "Purchase Successful"), isPresented: $membershipManager.showSuccessAlert) {
            Button(String(localized: "OK")) {
                hasShownMembership = true
                dismiss()
            }
        } message: {
            Text(String(localized: "Thank you for your support!"))
        }
        .alert(String(localized: "Notice"), isPresented: .constant(membershipManager.purchaseError != nil)) {
            Button(String(localized: "OK")) {
                membershipManager.purchaseError = nil
            }
        } message: {
            if let error = membershipManager.purchaseError {
                Text(error)
            }
        }
    }

    // MARK: - Scroll View

    private var scrollView: some View {
        ScrollView {
            VStack(spacing: 28) {
                headerSection
                productCardsSection
                benefitsSection
                termsSection
            }
            .padding(.top, isMandatory ? 40 : 60)
            .padding(.bottom, 24)
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)  // 隐藏滚动条
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .scrollIndicators(.hidden)  // 隐藏滚动条
    }

    // MARK: - Close Button

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    hasShownMembership = true
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .padding(.trailing, 20)
                .padding(.top, 10)
            }
            Spacer()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image("WelcomeIcon")
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            Text(String(localized: "Upgrade to Pro"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(String(localized: "Unlock All Features"))
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Membership Benefits"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.bottom, 2)

            benefitRow(icon: "sparkles",
                       title: String(localized: "Benefit AI Similar"),
                       subtitle: String(localized: "Benefit AI Similar Sub"))
            benefitRow(icon: "wand.and.stars",
                       title: String(localized: "Benefit AI Junk"),
                       subtitle: String(localized: "Benefit AI Junk Sub"))
            benefitRow(icon: "doc.on.doc",
                       title: String(localized: "Benefit Duplicates"),
                       subtitle: String(localized: "Benefit Duplicates Sub"))
            benefitRow(icon: "calendar",
                       title: String(localized: "Benefit Smart Grouping"),
                       subtitle: String(localized: "Benefit Smart Grouping Sub"))
            benefitRow(icon: "plus.rectangle.on.rectangle",
                       title: String(localized: "Benefit Album Complete"),
                       subtitle: String(localized: "Benefit Album Complete Sub"))
            benefitRow(icon: "internaldrive",
                       title: String(localized: "Benefit Cleanup Tools"),
                       subtitle: String(localized: "Benefit Cleanup Tools Sub"))
            benefitRow(icon: "clock.arrow.circlepath",
                       title: String(localized: "Benefit Memories"),
                       subtitle: String(localized: "Benefit Memories Sub"))
            benefitRow(icon: "square.grid.2x2",
                       title: String(localized: "Benefit Browsing"),
                       subtitle: String(localized: "Benefit Browsing Sub"))
        }
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.blue)
        }
    }

    // MARK: - Product Cards

    private var productCardsSection: some View {
        VStack(spacing: 12) {
            ForEach(SubscriptionType.allCases, id: \.self) { productType in
                ProductCard(
                    productType: productType,
                    products: membershipManager.products,
                    isSelected: membershipManager.selectedProduct == productType,
                    onTap: {
                        withAnimation(.spring(response: 0.3)) {
                            membershipManager.selectedProduct = productType
                        }
                    }
                )
            }
        }
    }

    // MARK: - Terms

    private var termsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Subscription Terms"))
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                if membershipManager.hasFreeTrialOffer {
                    Text(String(localized: "• After the free trial ends, your subscription automatically renews unless canceled at least 24 hours before it ends."))
                }
                Text(String(localized: "• Subscription will auto-renew unless turned off at least 24 hours before the current period ends."))
                Text(String(localized: "• Your account will be charged for renewal within 24 hours before the current period ends."))
                Text(String(localized: "• You can manage your subscription and turn off auto-renewal after purchase."))
            }
            .font(.system(size: 11, design: .rounded))
            .foregroundColor(Color(.tertiaryLabel))

            HStack(spacing: 24) {
                Link(String(localized: "Terms of Use"),
                     destination: URL(string: "https://sealandsky.github.io/privacy/terms-of-use.html")!)
                Link(String(localized: "Privacy Policy"),
                     destination: privacyPolicyURL)
            }
            .font(.system(size: 11, design: .rounded))
        }
    }

    /// 隐私政策按设备语言跳转对应版本
    private var privacyPolicyURL: URL {
        let isChinese = Locale.current.language.languageCode?.identifier == "zh"
        return URL(string: isChinese
            ? "https://sealandsky.github.io/privacy/privacy-policy-zh.html"
            : "https://sealandsky.github.io/privacy/privacy-policy.html")!
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)

            VStack(spacing: 10) {
                Button {
                    Task {
                        await membershipManager.purchase(membershipManager.selectedProduct)
                    }
                } label: {
                    if membershipManager.isLoadingPurchase {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if membershipManager.selectedProduct.hasFreeTrial(from: membershipManager.products) {
                        Text(String(localized: "Start Free Trial"))
                    } else {
                        Text(String(localized: "Subscribe"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(membershipManager.isLoadingPurchase)

                // 扣费披露：明确试用时长与试用结束后将自动收取的金额（App Store 审核 3.1.2 要求）
                if let disclosure = membershipManager.selectedProduct.purchaseDisclosureText(from: membershipManager.products) {
                    Text(disclosure)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await membershipManager.restorePurchases()
                        }
                    } label: {
                        Text(String(localized: "Restore Purchases"))
                    }

                    if !isMandatory {
                        Text("·")
                            .foregroundColor(.secondary)

                        Button {
                            hasShownMembership = true
                            dismiss()
                        } label: {
                            Text(String(localized: "Later"))
                        }
                    }
                }
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        Color.black.opacity(0.15)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                        .scaleEffect(1.5)

                    Text(String(localized: "Processing..."))
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.primary)
                }
            }
    }
}

#Preview {
    MembershipView(isMandatory: false)
}
