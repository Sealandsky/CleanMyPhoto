

import SwiftUI
import StoreKit

struct ProductCard: View {
    let productType: SubscriptionType
    let products: [Product]
    let isSelected: Bool
    /// 当前 Apple ID 的试用资格：无资格时不展示试用徽章
    var eligibleForIntroOffer: Bool = true
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 左侧：产品名称与精炼标签
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(productType.displayName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)

                        if productType.isPopular {
                            popularBadge
                        }

                        if productType == .lifetime {
                            launchSpecialBadge
                        }
                    }

                    HStack(spacing: 6) {
                        if let trial = productType.trialBadgeText(
                            from: products,
                            eligibleForIntroOffer: eligibleForIntroOffer
                        ) {
                            trialBadge(trial)
                        }

                        if let savings = productType.savingsText {
                            savingsBadge(savings)
                        }

                        if let subtitle = productType.subtitleText {
                            Text(subtitle)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // 右侧：价格与周期
                VStack(alignment: .trailing, spacing: 2) {
                    if let price = productType.priceText(from: products) {
                        priceView(price: price)
                    } else {
                        Text(String(localized: "Price Unavailable"))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(cardBackground)
            .overlay(borderOverlay)
            .shadow(
                color: isSelected ? Color.blue.opacity(0.12) : Color.black.opacity(0.03),
                radius: isSelected ? 8 : 3,
                x: 0,
                y: isSelected ? 3 : 1
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Price View
    @ViewBuilder
    private func priceView(price: String) -> some View {
        if productType == .yearly {
            // 年度订阅：主价格显示 ¥58.00/年，副文案写“折合 ¥4.83/月”
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(price)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(productType.durationText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            if let monthlyEq = productType.monthlyEquivalentPriceText(from: products) {
                Text(monthlyEq)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        } else if productType == .monthly {
            // 月度订阅：显示月价与周期，副文案说明按月续订
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(price)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(productType.durationText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Text(String(localized: "Auto-renews monthly"))
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(Color(UIColor.secondaryLabel))
        } else {
            // 终身会员：主价格显示 ¥88.00，下方显示“原价：~~¥168.00~~”
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(price)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            (
                Text(String(localized: "Original Price:"))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                + Text(productType.lifetimeOriginalPriceText(from: products))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .strikethrough(true, color: Color(UIColor.tertiaryLabel))
            )
        }
    }

    // MARK: - Card Background
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? Color.blue.opacity(0.06) : Color(UIColor.secondarySystemGroupedBackground))
    }

    // MARK: - Border Overlay
    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                isSelected ? Color.blue : Color(UIColor.separator).opacity(0.35),
                lineWidth: isSelected ? 1.5 : 0.8
            )
    }

    // MARK: - Badges
    private var popularBadge: some View {
        Text(String(localized: "Most Popular"))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0, green: 0.45, blue: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var launchSpecialBadge: some View {
        Text(String(localized: "Launch Special"))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.45, blue: 0.15), Color(red: 0.95, green: 0.25, blue: 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private func trialBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(Color(red: 0.1, green: 0.58, blue: 0.32))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                Capsule()
                    .fill(Color(red: 0.1, green: 0.58, blue: 0.32).opacity(0.12))
            )
    }

    private func savingsBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(Color(red: 0.95, green: 0.42, blue: 0.1))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                Capsule()
                    .fill(Color(red: 0.95, green: 0.42, blue: 0.1).opacity(0.12))
            )
    }
}

#Preview {
    VStack(spacing: 12) {
        ProductCard(
            productType: .monthly,
            products: [],
            isSelected: false,
            onTap: {}
        )

        ProductCard(
            productType: .yearly,
            products: [],
            isSelected: true,
            onTap: {}
        )

        ProductCard(
            productType: .lifetime,
            products: [],
            isSelected: false,
            onTap: {}
        )
    }
    .padding()
}
