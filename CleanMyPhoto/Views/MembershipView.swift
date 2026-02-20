//
//  MembershipView.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/21.
//

import SwiftUI

struct MembershipView: View {
    @StateObject private var membershipManager = MembershipManager()
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

            if membershipManager.isLoadingPurchase {
                loadingOverlay
            }
        }
        .background(Color.black)
        .navigationBarHidden(true)
        .alert("购买成功", isPresented: $membershipManager.showSuccessAlert) {
            Button("确定") {
                hasShownMembership = true
                dismiss()
            }
        } message: {
            Text("感谢您的支持！")
        }
        .alert("提示", isPresented: .constant(membershipManager.purchaseError != nil)) {
            Button("确定") {
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
                Text("升级到专业版")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("解锁所有功能")
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
            Text("会员权益")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "checkmark.circle.fill", text: "无限制使用")
                benefitRow(icon: "checkmark.circle.fill", text: "未来功能升级")
                benefitRow(icon: "checkmark.circle.fill", text: "优先支持")
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
            Text("订阅说明")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))

            VStack(alignment: .leading, spacing: 8) {
                Text("• 订阅将自动续订，除非在当前期间结束前至少 24 小时关闭自动续订")
                Text("• 账户将在当前期间结束前 24 小时内收取续订费用")
                Text("• 用户可以管理订阅，购买后可以关闭自动续订")
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
                        Text("继续")
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
                Text("恢复购买")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
            }
            .disabled(membershipManager.isLoadingPurchase)

            if !isMandatory {
                Button {
                    hasShownMembership = true
                    dismiss()
                } label: {
                    Text("稍后升级")
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

                    Text("处理中...")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
            }
    }
}

#Preview {
    MembershipView(isMandatory: false)
}
