import SwiftUI
import Photos

// MARK: - On This Day Card Button Style
private struct OnThisDayCardPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - On This Day Card View
/// 「过去的今天」年份卡片单体组件：
/// - 精简小尺寸：100 × 136 pt；
/// - 纯净内容：左下角仅保留年份与照片张数；
/// - 质感设计：加配白色描边（strokeBorder）与柔和立体投影（shadow）。
struct OnThisDayCardView: View {
    let group: OnThisDayYearGroup
    var onTap: () -> Void

    @State private var imageLoaded = false

    private static let cardWidth: CGFloat = 100
    private static let cardHeight: CGFloat = 136
    private static let cornerRadius: CGFloat = 14

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            ZStack(alignment: .bottomLeading) {
                // 1. 底层封面素材
                coverLayer

                // 2. 底部暗色遮罩与左下角年份、照片数
                bottomOverlay
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2.5)
            )
            .shadow(color: Color.black.opacity(0.13), radius: 9, x: 0, y: 6.5)
        }
        .buttonStyle(OnThisDayCardPressButtonStyle())
    }

    // MARK: - Cover Layer
    private var coverLayer: some View {
        ZStack {
            Color(UIColor.secondarySystemFill)

            if !imageLoaded {
                Color.clear
                    .shimmering(cornerRadius: Self.cornerRadius)
            }

            AssetImage(
                asset: group.coverAsset.asset,
                targetSize: CGSize(width: 240, height: 320),
                contentMode: .fill,
                placeholderColor: Color.clear,
                onLoad: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        imageLoaded = true
                    }
                }
            )
            .scaledToFill()
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .clipped()
            .opacity(imageLoaded ? 1 : 0)
        }
    }

    // MARK: - Bottom Overlay (仅年份与照片数，左下角对齐)
    private var bottomOverlay: some View {
        VStack {
            Spacer()
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.25), Color.black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 54)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 1) {
                // 年份（如 2023）
                Text(String(group.year))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // 照片数量（如 24 Photos / 24 张）
                Text(String(localized: "\(group.photoCount) Photos"))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
            }
            .shadow(color: Color.black.opacity(0.5), radius: 2.5, x: 0, y: 1)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}
