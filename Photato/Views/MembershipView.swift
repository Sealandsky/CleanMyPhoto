

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

            // 强制付费墙也保留可见的关闭按钮：唯一逃生通道是不可见的下滑手势
            // 会同时伤害审核评价与用户信任
            closeButton

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
            VStack(spacing: 22) {
                headerSection
                productCardsSection
                benefitsSection
                termsSection
            }
            .padding(.top, isMandatory ? 24 : 40)
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                if #available(iOS 26.0, *) {
                    Button {
                        hasShownMembership = true
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                } else {
                    Button {
                        hasShownMembership = true
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .padding(.trailing, 16)
            .padding(.top, 10)
            Spacer()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            Image("WelcomeIcon")
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)

            VStack(spacing: 4) {
                Text(String(localized: "Upgrade to Pro"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(String(localized: "Unlock permanent deletion & all AI cleanup"))
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Membership Benefits"))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.bottom, 2)

            benefitRow(icon: "lock.open.fill",
                       title: String(localized: "Benefit Permanent Delete"),
                       subtitle: String(localized: "Benefit Permanent Delete Sub"))
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color.blue.opacity(0.85))
        }
    }

    // MARK: - Product Cards

    private var productCardsSection: some View {
        VStack(spacing: 10) {
            if membershipManager.products.isEmpty {
                productsUnavailableView
            } else {
                ForEach(SubscriptionType.allCases, id: \.self) { productType in
                    ProductCard(
                        productType: productType,
                        products: membershipManager.products,
                        isSelected: membershipManager.selectedProduct == productType,
                        eligibleForIntroOffer: membershipManager.isEligibleForIntroOffer,
                        onTap: {
                            withAnimation(.spring(response: 0.3)) {
                                membershipManager.selectedProduct = productType
                            }
                        }
                    )
                }
            }
        }
    }

    /// 商品未就绪：首次拉取显示加载态；失败后显示重试入口（不再弹全局错误）
    @ViewBuilder
    private var productsUnavailableView: some View {
        if membershipManager.isLoadingProducts {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else {
            VStack(spacing: 12) {
                Text(String(localized: "Couldn't load subscription options"))
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await membershipManager.reloadProducts() }
                } label: {
                    Text(String(localized: "Retry"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 8)
                }
                .background(
                    Capsule().fill(Color.blue.opacity(0.12))
                )
                .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
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
        VStack(spacing: 10) {
            Button {
                Task {
                    await membershipManager.purchase(membershipManager.selectedProduct)
                }
            } label: {
                if membershipManager.isLoadingPurchase {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(membershipManager.selectedProduct.actionButtonTitle(
                        from: membershipManager.products,
                        eligibleForIntroOffer: membershipManager.isEligibleForIntroOffer
                    ))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(membershipManager.isLoadingPurchase || membershipManager.products.isEmpty)

            // 扣费披露：明确试用时长与试用结束后将自动收取的金额（App Store 审核 3.1.2 要求）
            if let disclosure = membershipManager.selectedProduct.purchaseDisclosureText(
                from: membershipManager.products,
                eligibleForIntroOffer: membershipManager.isEligibleForIntroOffer
            ) {
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
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().opacity(0.4)
                }
                .ignoresSafeArea(edges: .bottom)
        )
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
