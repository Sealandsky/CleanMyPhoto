//
//  MembershipManager.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/21.
//

import SwiftUI
import StoreKit
import Combine

// MARK: - Store Error
enum MembershipError: Error {
    case failedVerification
    case productNotFound
    case purchaseFailed(String)
}

// MARK: - Membership Manager
@MainActor
class MembershipManager: ObservableObject {
    // MARK: - Published Properties
    @Published var membershipStatus: MembershipStatus
    @Published var selectedProduct: SubscriptionType = .yearly
    @Published var isLoadingPurchase = false
    @Published var purchaseError: String?
    @Published var showSuccessAlert = false

    // MARK: - StoreKit Properties
    @Published var products: [Product] = []
    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Computed Properties
    var isTrialExpired: Bool {
        guard let expirationDate = membershipStatus.trialExpirationDate else {
            return false
        }
        return Date() > expirationDate && membershipStatus.currentTier == .free
    }

    var remainingTrialDays: Int {
        membershipStatus.remainingTrialDays ?? 0
    }

    var isPremiumMember: Bool {
        membershipStatus.isPremiumMember
    }

    // MARK: - Init
    init() {
        // 从 UserDefaults 加载状态
        self.membershipStatus = MembershipStatus.loadFromStorage()

        // 启动首次试用计时
        startTrialIfNeeded()

        // 监听 StoreKit 更新
        updateListenerTask = listenForTransactions()

        // 加载产品
        Task {
            await loadProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Trial Management
    private func startTrialIfNeeded() {
        if membershipStatus.trialStartDate == nil {
            membershipStatus.trialStartDate = Date()
            membershipStatus.saveToStorage()
            print("🎉 Trial started at: \(membershipStatus.trialStartDate!)")
        }
    }

    func checkTrialStatus() -> Bool {
        return membershipStatus.isTrialActive
    }

    // MARK: - StoreKit Integration
    private func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: SubscriptionType.allCases.map { $0.rawValue })
            self.products = storeProducts.sorted { $0.price < $1.price }
            print("✅ Loaded \(products.count) products")
        } catch {
            print("❌ Failed to load products: \(error.localizedDescription)")
            self.purchaseError = "加载产品失败: \(error.localizedDescription)"
        }
    }

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in StoreKit.Transaction.updates {
                await MainActor.run {
                    self.handleTransactionUpdate(result)
                }
            }
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<StoreKit.Transaction>) {
        do {
            let transaction = try checkVerified(result)

            // 检查是否是我们的产品
            let productID = transaction.productID
            if SubscriptionType.allCases.contains(where: { $0.rawValue == productID }) {
                // 更新会员状态
                updateMembershipStatus(from: productID)
                print("✅ Transaction verified: \(productID)")

                // 完成交易
                Task.detached {
                    await transaction.finish()
                }
            }
        } catch {
            print("❌ Transaction verification failed: \(error.localizedDescription)")
        }
    }

    func purchase(_ productType: SubscriptionType) async {
        guard let product = products.first(where: { $0.id == productType.rawValue }) else {
            self.purchaseError = "产品未找到"
            return
        }

        isLoadingPurchase = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                print("✅ Purchase successful")
                let transaction = try checkVerified(verification)
                await updateMembershipStatus(for: productType)

                await transaction.finish()
                showSuccessAlert = true

            case .userCancelled:
                print("ℹ️ Purchase cancelled by user")

            case .pending:
                print("⏳ Purchase pending")
                purchaseError = "购买等待确认"

            @unknown default:
                break
            }
        } catch {
            print("❌ Purchase failed: \(error.localizedDescription)")
            purchaseError = "购买失败: \(error.localizedDescription)"
        }

        isLoadingPurchase = false
    }

    func restorePurchases() async {
        isLoadingPurchase = true
        purchaseError = nil

        do {
            try await AppStore.sync()
            print("✅ Purchases restored")
            purchaseError = nil
        } catch {
            print("❌ Restore failed: \(error.localizedDescription)")
            purchaseError = "恢复购买失败: \(error.localizedDescription)"
        }

        isLoadingPurchase = false
    }

    private func updateMembershipStatus(for productType: SubscriptionType) async {
        let tier: MembershipTier
        switch productType {
        case .monthly:
            tier = .monthly
        case .yearly:
            tier = .yearly
        case .lifetime:
            tier = .lifetime
        }

        membershipStatus.currentTier = tier
        membershipStatus.saveToStorage()
        print("💳 Membership updated to: \(tier.rawValue)")
    }

    private func updateMembershipStatus(from productID: String) {
        if let productType = SubscriptionType.allCases.first(where: { $0.rawValue == productID }) {
            let tier: MembershipTier
            switch productType {
            case .monthly:
                tier = .monthly
            case .yearly:
                tier = .yearly
            case .lifetime:
                tier = .lifetime
            }

            membershipStatus.currentTier = tier
            membershipStatus.saveToStorage()
            print("💳 Membership updated from transaction: \(tier.rawValue)")
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw MembershipError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}
