//
//  MembershipView.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/21.
//

import SwiftUI

struct MembershipView: View {
    @EnvironmentObject private var membershipManager: MembershipManager
    @AppStorage("hasShownMembership") private var hasShownMembership: Bool = false
    @Environment(\.dismiss) private var dismiss

    let isMandatory: Bool // 是否强制显示（试用结束后）

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    productCardsSection
                    benefitsSection
                    termsSection
                    actionButtons
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
            }

            // 关闭按钮
            VStack {
                HStack {
                    Spacer()
                    Button {
                        hasShownMembership = true
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(22)
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 10)
                }
                Spacer()
            }

            if membershipManager.isLoadingPurchase {
                loadingOverlay
            }
        }
        .background(Color(white: 0.12))
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

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image("WelcomeIcon")
                .resizable()
                .frame(width: 80, height: 80)
                .cornerRadius(22)

            VStack(spacing: 8) {
                Text(String(localized: "Upgrade to Pro"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text(String(localized: "Unlock All Features"))
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Product Cards
    private var productCardsSection: some View {
        VStack(spacing: 16) {
            ForEach(SubscriptionType.allCases, id: \.self) { productType in
                ProductCard(
                    productType: productType,
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

    // MARK: - Benefits
    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Membership Benefits"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "checkmark.circle.fill", text: String(localized: "Unlimited Usage"))
                benefitRow(icon: "checkmark.circle.fill", text: String(localized: "Future Upgrades"))
                benefitRow(icon: "checkmark.circle.fill", text: String(localized: "Priority Support"))
            }
        }
        .padding(.horizontal, 4)
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)

            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.white)

            Spacer()
        }
    }

    // MARK: - Terms
    private var termsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Subscription Terms"))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "• Subscription will auto-renew unless turned off at least 24 hours before the current period ends."))
                Text(String(localized: "• Your account will be charged for renewal within 24 hours before the current period ends."))
                Text(String(localized: "• You can manage your subscription and turn off auto-renewal after purchase."))
            }
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await membershipManager.purchase(membershipManager.selectedProduct)
                }
            } label: {
                HStack {
                    if membershipManager.isLoadingPurchase {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(String(localized: "Continue"))
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(Color("PrimaryBtn"))
                .cornerRadius(22)
            }
            .disabled(membershipManager.isLoadingPurchase)

            Button {
                Task {
                    await membershipManager.restorePurchases()
                }
            } label: {
                Text(String(localized: "Restore Purchases"))
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
            }
            .disabled(membershipManager.isLoadingPurchase)

            if !isMandatory {
                Button {
                    hasShownMembership = true
                    dismiss()
                } label: {
                    Text(String(localized: "Later"))
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        Color.black.opacity(0.8)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)

                    Text(String(localized: "Processing..."))
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
            }
    }
}

#Preview {
    MembershipView(isMandatory: false)
}
