

import SwiftUI

struct MembershipView: View {
    @EnvironmentObject private var membershipManager: MembershipManager
    @AppStorage("hasShownMembership") private var hasShownMembership: Bool = false
    @Environment(\.dismiss) private var dismiss

    let isMandatory: Bool

    var body: some View {
        ZStack {
            Color(white: 0.06)
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
                benefitsSection
                productCardsSection
                termsSection
            }
            .padding(.top, isMandatory ? 40 : 60)
            .padding(.bottom, 24)
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
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
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)

            if membershipManager.remainingTrialDays > 0,
               let text = membershipManager.remainingTrialText {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
            } else {
                Text(String(localized: "Unlock All Features"))
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Membership Benefits"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(.bottom, 2)

            benefitRow(icon: "doc.on.doc",
                       title: String(localized: "Benefit Duplicate"),
                       subtitle: String(localized: "Benefit Duplicate Sub"))
            benefitRow(icon: "photo.on.rectangle.angled",
                       title: String(localized: "Benefit Screenshot"),
                       subtitle: String(localized: "Benefit Screenshot Sub"))
            benefitRow(icon: "internaldrive",
                       title: String(localized: "Benefit Large File"),
                       subtitle: String(localized: "Benefit Large File Sub"))
            benefitRow(icon: "rectangle.and.text.magnifyingglass",
                       title: String(localized: "Benefit Low Quality"),
                       subtitle: String(localized: "Benefit Low Quality Sub"))
            benefitRow(icon: "trash.circle",
                       title: String(localized: "Benefit Batch Delete"),
                       subtitle: String(localized: "Benefit Batch Delete Sub"))
            benefitRow(icon: "hand.draw",
                       title: String(localized: "Benefit Fullscreen"),
                       subtitle: String(localized: "Benefit Fullscreen Sub"))
            benefitRow(icon: "square.grid.2x2",
                       title: String(localized: "Benefit Grid Layout"),
                       subtitle: String(localized: "Benefit Grid Layout Sub"))
        }
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
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
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "• Subscription will auto-renew unless turned off at least 24 hours before the current period ends."))
                Text(String(localized: "• Your account will be charged for renewal within 24 hours before the current period ends."))
                Text(String(localized: "• You can manage your subscription and turn off auto-renewal after purchase."))
            }
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.35))
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

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
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                            LinearGradient(
                                colors: [Color(red: 0, green: 0.52, blue: 1.0), Color(red: 0, green: 0.72, blue: 1.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(membershipManager.isLoadingPurchase)

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
                            .foregroundColor(.white.opacity(0.3))

                        Button {
                            hasShownMembership = true
                            dismiss()
                        } label: {
                            Text(String(localized: "Later"))
                        }
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(white: 0.08))
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
