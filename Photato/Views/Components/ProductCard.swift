

import SwiftUI
import StoreKit

struct ProductCard: View {
    let productType: SubscriptionType
    let products: [Product]
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // 左侧：产品名称和标签
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(productType.displayName)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(.white)

                        if productType.isPopular {
                            popularBadge
                        }
                    }

                    if let subtitle = productType.subtitleText {
                        Text(subtitle)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    if let savings = productType.savingsText {
                        Text(savings)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                }

                Spacer()

                // 右侧：价格
                VStack(alignment: .trailing, spacing: 2) {
                    Text(productType.priceText(from: products))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(productType.durationText.isEmpty ? String(localized: "One-time") : productType.durationText)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(20)
            .background(cardBackground)
            .overlay(borderOverlay)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Card Background
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
    }

    // MARK: - Border Overlay
    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 22)
            .stroke(strokeColor, lineWidth: isSelected ? 2 : 0)
    }

    // MARK: - Stroke Color
    private var strokeColor: Color {
        if isSelected && productType.isPopular {
            return Color.blue
        } else if isSelected {
            return Color.white.opacity(0.3)
        } else {
            return Color.clear
        }
    }

    // MARK: - Popular Badge
    private var popularBadge: some View {
        Text(String(localized: "Most Popular"))
            .font(.system(size: 11, design: .rounded))
            .fontWeight(.medium)
            .foregroundColor(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(8)
    }
}

#Preview {
    VStack(spacing: 16) {
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
    .background(Color.black)
}
