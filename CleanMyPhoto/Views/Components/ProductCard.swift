//
//  ProductCard.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/21.
//

import SwiftUI

struct ProductCard: View {
    let productType: SubscriptionType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // 左侧：产品名称和标签
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(productType.displayName)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)

                        if productType.isPopular {
                            popularBadge
                        }
                    }

                    if let subtitle = productType.subtitleText {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    if let savings = productType.savingsText {
                        Text(savings)
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                }

                Spacer()

                // 右侧：价格
                VStack(alignment: .trailing, spacing: 2) {
                    Text(productType.priceText)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text(productType.durationText.isEmpty ? "一次性" : productType.durationText)
                        .font(.system(size: 13))
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
        Text("最受欢迎")
            .font(.system(size: 11))
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
            isSelected: false,
            onTap: {}
        )

        ProductCard(
            productType: .yearly,
            isSelected: true,
            onTap: {}
        )

        ProductCard(
            productType: .lifetime,
            isSelected: false,
            onTap: {}
        )
    }
    .padding()
    .background(Color.black)
}
