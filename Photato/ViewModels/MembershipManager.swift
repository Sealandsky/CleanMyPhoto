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
    /// 当前 Apple ID 是否有资格使用 introductory offer（已消耗过试用的用户为 false）
    @Published private(set) var isEligibleForIntroOffer = true
    /// 商品列表加载状态（付费墙据此区分「加载中」与「加载失败可重试」）
    @Published private(set) var isLoadingProducts = false
    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Computed Properties
    /// 任一订阅配置了免费试用且当前 Apple ID 有资格（用于条款区试用说明）
    var hasFreeTrialOffer: Bool {
        products.contains { $0.subscription?.introductoryOffer?.paymentMode == .freeTrial }
            && isEligibleForIntroOffer
    }

    #if DEBUG
    @Published var isDebugPremium = false

    /// 调试方法：重置免费额度（已消耗数归零）
    func resetFreeQuotaForTesting() {
        freeDeletionsUsed = 0
        UserDefaults.standard.set(0, forKey: Self.freeDeletionsUsedKey)
    }

    /// 调试方法：耗尽免费额度（已消耗数设为上限）
    func exhaustFreeQuotaForTesting() {
        freeDeletionsUsed = Self.freeDeletionQuota
        UserDefaults.standard.set(freeDeletionsUsed, forKey: Self.freeDeletionsUsedKey)
    }
    #endif

    var isPremiumMember: Bool {
        #if DEBUG
        return isDebugPremium
        #else
        return membershipStatus.isPremiumMember
        #endif
    }

    // MARK: - 免费删除额度
    /// 免费用户的一次性永久删除额度：仅对非会员生效（会员含试用期内不扣不减）。
    /// 在清空回收站（永久删除）成功后按张数消耗，上限封顶。
    static let freeDeletionQuota = 100
    private static let freeDeletionsUsedKey = "freeDeletionsUsed"

    /// 已消耗的免费删除张数（UserDefaults 持久化，一次性额度不随会员状态复位）
    @Published private(set) var freeDeletionsUsed: Int

    /// 剩余免费删除张数（钳制 ≥0）
    var freeDeletionsRemaining: Int {
        max(0, Self.freeDeletionQuota - freeDeletionsUsed)
    }

    /// 是否还有免费额度可用于永久删除
    var hasFreeDeletionQuota: Bool {
        freeDeletionsRemaining > 0
    }

    /// 额度展示文案：会员「无限」；免费显示剩余/总额；用尽提示升级
    var quotaDisplayText: String {
        if isPremiumMember {
            return String(localized: "Unlimited (Member)")
        }
        if freeDeletionsRemaining > 0 {
            return String(localized: "Free Deletion Quota Value \(freeDeletionsRemaining)")
        }
        return String(localized: "Free Quota Exhausted Value")
    }

    /// 消耗免费删除额度：仅非会员生效；消耗数封顶为剩余额度。
    /// 在 emptyTrash 实际删除成功后调用（失败路径不调用，不扣）
    func consumeFreeDeletions(_ count: Int) {
        guard !isPremiumMember, count > 0 else { return }
        freeDeletionsUsed = min(freeDeletionsUsed + count, Self.freeDeletionQuota)
        UserDefaults.standard.set(freeDeletionsUsed, forKey: Self.freeDeletionsUsedKey)
    }

    // MARK: - Init
    init() {
        // 从 UserDefaults 快速恢复本地会员身份与免费额度，0 毫秒完成
        self.membershipStatus = MembershipStatus.loadFromStorage()
        self.freeDeletionsUsed = UserDefaults.standard.integer(forKey: Self.freeDeletionsUsedKey)

        // 监听 StoreKit 交易更新（苹果规范后台流，无交易时挂起零开销）
        updateListenerTask = listenForTransactions()

        // 商品与权益改为在用户真正打开付费页时按需加载，彻底免除启动期网络 I/O 与并发争抢
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - StoreKit Integration

    /// 商品自动重试间隔（1s / 3s）。StoreKit 2 冷缓存已知行为：首次请求可能
    /// 返回空数组或失败，第二次起命中本地缓存；自动重试后仍失败才交给付费墙手动重试
    private static let productLoadRetryDelays: [UInt64] = [1_000_000_000, 3_000_000_000]

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        // 诊断：xcode = 本地 .storekit 配置已注入；sandbox = 未注入（走沙盒网络）
        do {
            let appTransaction = try await AppTransaction.shared
            switch appTransaction {
            case .verified(let tx):
                print("🧪 StoreKit environment: \(tx.environment.rawValue)")
            case .unverified(_, let error):
                print("🧪 StoreKit environment: unverified(\(error.localizedDescription))")
            }
        } catch {
            print("🧪 StoreKit environment: unavailable(\(error.localizedDescription))")
        }

        for attempt in 0...Self.productLoadRetryDelays.count {
            do {
                let storeProducts = try await Product.products(for: SubscriptionType.allCases.map { $0.rawValue })
                if !storeProducts.isEmpty {
                    self.products = storeProducts.sorted { $0.price < $1.price }
                    await refreshIntroOfferEligibility()
                    print("✅ Loaded \(products.count) products (attempt \(attempt + 1))")
                    return
                }
                // 空结果视为未就绪，进入重试（StoreKit 首次调用的已知行为）
                print("⚠️ Products empty on attempt \(attempt + 1)")
            } catch {
                print("❌ Failed to load products (attempt \(attempt + 1)): \(error.localizedDescription)")
            }

            if attempt < Self.productLoadRetryDelays.count {
                try? await Task.sleep(nanoseconds: Self.productLoadRetryDelays[attempt])
            }
        }
        // 全部尝试失败：products 保持为空，付费墙显示手动重试入口
    }

    /// 确保商品与权益已就绪（付费页打开时按需调用，内存已有商品时直接秒显复用）
    func ensureProductsLoaded() async {
        if products.isEmpty {
            await loadProducts()
        }
        await refreshEntitlements()
    }

    /// 付费墙「重试」入口：重新拉取商品并刷新试用资格与权益
    func reloadProducts() async {
        await loadProducts()
        await refreshEntitlements()
    }

    /// App Store 试用资格校验：已消耗过 introductory offer 的 Apple ID 不再展示试用文案，
    /// 避免「按钮承诺试用、实际立即扣费」的口径错位
    private func refreshIntroOfferEligibility() async {
        guard let monthlySubscription = products.first(where: {
            $0.id == SubscriptionType.monthly.rawValue
        })?.subscription else {
            isEligibleForIntroOffer = false
            return
        }
        isEligibleForIntroOffer = await monthlySubscription.isEligibleForIntroOffer
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
            // 用户主动取消购买：静默返回，不弹任何提示
            let nsError = error as NSError
            if nsError.domain == "SKErrorDomain", nsError.code == SKError.Code.paymentCancelled.rawValue {
                print("ℹ️ Purchase cancelled by user")
            } else {
                print("❌ Purchase failed: \(error.localizedDescription)")
                purchaseError = friendlyErrorMessage(error)
            }
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
        // StoreKit 层错误（家长审批拒绝、支付失败等）：用户取消已在调用方静默处理，
        // 其余给通用文案，不再误报为网络错误
        if (error as NSError).domain == "SKErrorDomain" {
            return String(localized: "Purchase could not be completed. Please try again.")
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
