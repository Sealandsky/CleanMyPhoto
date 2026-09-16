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

    var remainingTrialText: String? {
        membershipStatus.remainingTrialText
    }

    /// 任一订阅配置了免费试用（用于付费墙展示试用条款）
    var hasFreeTrialOffer: Bool {
        products.contains { $0.subscription?.introductoryOffer?.paymentMode == .freeTrial }
    }

    #if DEBUG
    @Published var isDebugPremium = false
    #endif

    var isPremiumMember: Bool {
        #if DEBUG
        return isDebugPremium
        #else
        return membershipStatus.isPremiumMember
        #endif
    }

    // MARK: - Init
    init() {
        // 从 UserDefaults 加载状态
        self.membershipStatus = MembershipStatus.loadFromStorage()

        // 启动首次试用计时
        startTrialIfNeeded()

        // 监听 StoreKit 更新
        updateListenerTask = listenForTransactions()

        // 加载产品并校验当前权益（订阅到期/退款后自动降级）
        Task {
            await loadProducts()
            await refreshEntitlements()
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
            self.purchaseError = friendlyErrorMessage(error)
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
                // 以当前有效权益为准（退款/到期推送也会走到这里，触发自动降级）
                Task {
                    await refreshEntitlements()
                }
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
            self.purchaseError = String(localized: "Product not found")
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
                await refreshEntitlements()

                await transaction.finish()
                showSuccessAlert = true

            case .userCancelled:
                print("ℹ️ Purchase cancelled by user")

            case .pending:
                print("⏳ Purchase pending")
                purchaseError = String(localized: "Purchase pending confirmation")

            @unknown default:
                break
            }
        } catch {
            print("❌ Purchase failed: \(error.localizedDescription)")
            purchaseError = friendlyErrorMessage(error)
        }

        isLoadingPurchase = false
    }

    func restorePurchases() async {
        isLoadingPurchase = true
        purchaseError = nil

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if membershipStatus.currentTier == .free {
                purchaseError = String(localized: "No purchases to restore")
            }
            print("✅ Purchases restored")
        } catch {
            print("❌ Restore failed: \(error.localizedDescription)")
            purchaseError = friendlyErrorMessage(error)
        }

        isLoadingPurchase = false
    }

    // MARK: - Entitlements

    /// 以 StoreKit 当前有效权益推导会员档位：
    /// 订阅到期、取消或退款后 currentEntitlements 不再包含对应交易，档位自动降回 free。
    private func refreshEntitlements() async {
        var bestTier = MembershipTier.free

        for await result in StoreKit.Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  let productType = SubscriptionType(rawValue: transaction.productID),
                  transaction.revocationDate == nil,                        // 已退款/撤销
                  transaction.expirationDate.map({ $0 > Date() }) ?? true   // 订阅未到期；一次性买断无到期日
            else { continue }

            let tier = membershipTier(for: productType)
            if tierRank(tier) > tierRank(bestTier) {
                bestTier = tier
            }
        }

        if membershipStatus.currentTier != bestTier {
            membershipStatus.currentTier = bestTier
            membershipStatus.saveToStorage()
            print("💳 Membership tier updated: \(bestTier.rawValue)")
        }
    }

    private func membershipTier(for productType: SubscriptionType) -> MembershipTier {
        switch productType {
        case .monthly: return .monthly
        case .yearly: return .yearly
        case .lifetime: return .lifetime
        }
    }

    private func tierRank(_ tier: MembershipTier) -> Int {
        switch tier {
        case .free: return 0
        case .monthly: return 1
        case .yearly: return 2
        case .lifetime: return 3
        }
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        let code = nsError.code
        let domain = nsError.domain

        // StoreKit network errors
        if domain == "SKErrorDomain" {
            if code == 0 {
                return String(localized: "Cannot connect to the App Store. Please check your network connection and try again.")
            } else if code == 2 {
                return String(localized: "Cannot connect to the App Store. Please check your network connection and try again.")
            }
        }

        // URLError / network errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return String(localized: "No internet connection. Please check your network and try again.")
            case .timedOut:
                return String(localized: "Connection timed out. Please try again.")
            case .cannotConnectToHost:
                return String(localized: "Cannot connect to the App Store. Please try again later.")
            default:
                break
            }
        }

        return error.localizedDescription
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
