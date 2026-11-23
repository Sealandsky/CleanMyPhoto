import SwiftUI

// MARK: - On This Day Collage View (Widget-safe)
/// 「往年今日」静态拼贴视图：输入是已经落盘的 UIImage，不依赖 Photos / 手势 / 滚动，
/// 因此可在 Widget 的静态 SwiftUI 环境中渲染。
///
/// 视觉语言与主 App 的 OnThisDaySectionView / OnThisDayYearPageView 一致：
/// - 暖色渐变底板铺满整个容器；
/// - 照片带自然倾斜角度（与 App 内 ScatteredPhotoCard 一致）；
/// - 小尺寸卡片（systemSmall）：标题置于顶部中央，照片在下方错落展开，后排照片略小形成纵深层次，尺寸适中、整体上移不贴底，左右与底部均留有呼吸空隙，展示多张（最多 3 张）；
/// - 中尺寸卡片（systemMedium）：标题靠左排版，照片集中在右侧做 4:3 比例错落堆叠展示。
struct OnThisDayCollageView: View {
    let images: [UIImage]
    let year: Int
    let photoCount: Int
    let isMonthFallback: Bool
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                // 1. 暖色渐变底板（铺满，四周无留白）
                OnThisDayVisualConstants.bannerGradient(isDark: isDark)

                // 2. 错落照片层（小卡居中靠下，中卡全部集中在右侧堆叠）
                collage(in: CGSize(width: w, height: h))

                // 3. 标题文字层
                if compact {
                    // 小卡：标题固定在顶部居中，左右预留防溢出安全边距
                    compactHeader
                        .padding(.horizontal, 10)
                        .frame(width: w, alignment: .center)
                        .padding(.top, max(12, h * 0.08))
                        .zIndex(10)
                } else {
                    // 中卡：标题靠左对齐，显式限制最大宽度（w * 0.32）并配合 dynamic scaling，
                    // 彻底杜绝多语言超长文本（如西语 "Un día como hoy"）与右侧照片重叠
                    mediumLeftHeader
                        .frame(maxWidth: max(96, w * 0.32), alignment: .leading)
                        .padding(.leading, max(22, w * 0.07))
                        .padding(.top, max(24, h * 0.16))
                        .zIndex(10)
                }
            }
            .frame(width: w, height: h)
        }
    }

    // MARK: - Compact Header (小卡专用顶部标题)
    @ViewBuilder
    private var compactHeader: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: "\(year)")
                    .font(.system(size: 19, weight: .bold, design: .rounded))

                let suffix = String(localized: "year_suffix", defaultValue: "")
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(OnThisDayVisualConstants.primaryText(isDark: isDark))
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: "\(photoCount)")
                Text(String(localized: "photos_count_suffix", defaultValue: " Photos"))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(OnThisDayVisualConstants.secondaryText(isDark: isDark))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Medium Left Header (大卡左侧标题)
    @ViewBuilder
    private var mediumLeftHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "On This Day"))
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundColor(OnThisDayVisualConstants.secondaryText(isDark: isDark))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: "\(year)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                let suffix = String(localized: "year_suffix", defaultValue: "")
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(OnThisDayVisualConstants.primaryText(isDark: isDark))
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: "\(photoCount)")
                Text(String(localized: "photos_count_suffix", defaultValue: " Photos"))
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(OnThisDayVisualConstants.secondaryText(isDark: isDark))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Collage
    @ViewBuilder
    private func collage(in size: CGSize) -> some View {
        let w = size.width
        let h = size.height

        if compact {
            // 小卡尺寸（正方形）：标题在上方，照片适度微缩并整体悬浮，后方两张较小且继续下移形成沉稳衬托
            let count = min(images.count, 3)
            if count >= 3 {
                // 3 张：主图 (0.39w × 0.49h)，后两张更小 (0.33w × 0.42h) 且继续下移，层次错落自然
                let frontW = w * 0.39
                let frontH = h * 0.49
                let backW = w * 0.33
                let backH = h * 0.42

                // 1. 左翼（images[1]）：左倾 -10°，较小尺寸，继续下移
                photoCard(images[1], width: backW, height: backH, rotation: .degrees(-10))
                    .offset(x: w * 0.11, y: h * 0.44)
                    .zIndex(1)

                // 2. 右翼（images[2]）：右倾 +9°，较小尺寸，继续下移
                photoCard(images[2], width: backW, height: backH, rotation: .degrees(9))
                    .offset(x: w * 0.55, y: h * 0.44)
                    .zIndex(2)

                // 3. 居中主图（images[0]）：顶层微倾 -2°，体量突出
                photoCard(images[0], width: frontW, height: frontH, rotation: .degrees(-2))
                    .offset(x: (w - frontW) / 2, y: h * 0.41)
                    .zIndex(3)
            } else if count == 2 {
                // 2 张：后方一张更小且继续下移
                let frontW = w * 0.40
                let frontH = h * 0.50
                let backW = w * 0.35
                let backH = h * 0.44

                // 底层后方左倾 -8°，较小并继续下移
                photoCard(images[0], width: backW, height: backH, rotation: .degrees(-8))
                    .offset(x: w * 0.16, y: h * 0.44)
                    .zIndex(1)

                // 顶层前方右倾 +7°
                photoCard(images[1], width: frontW, height: frontH, rotation: .degrees(7))
                    .offset(x: w * 0.46, y: h * 0.43)
                    .zIndex(2)
            } else if count == 1 {
                // 1 张：居中微倾，居中悬浮不贴底
                let cardW = w * 0.44
                let cardH = h * 0.55
                photoCard(images[0], width: cardW, height: cardH, rotation: .degrees(-4))
                    .offset(x: (w - cardW) / 2, y: h * 0.40)
                    .zIndex(1)
            }
        } else {
            // 中尺寸：参考堆叠样式，照片全部集中在右侧，最左侧卡片挪到底层，上图右倾 3°、下图左倾 3°
            let count = min(images.count, 4)
            // 4:3 比例，整体尺寸收敛
            let cardW = w * 0.31
            let cardH = cardW * 0.75

            if count >= 4 {
                // 1. 最左侧卡片（images[1]）：挪到底层，左倾 -8°，起手 0.42w 确保多语言长文案不碰撞
                photoCard(images[1], width: cardW, height: cardH, rotation: .degrees(-8))
                    .offset(x: w * 0.42, y: h * 0.25)
                    .zIndex(1)

                // 2. 顶部上图（images[3]）：往右旋转 3°
                photoCard(images[3], width: cardW, height: cardH, rotation: .degrees(3))
                    .offset(x: w * 0.52, y: h * 0.10)
                    .zIndex(2)

                // 3. 底部下图（images[2]）：往左旋转 3°
                photoCard(images[2], width: cardW, height: cardH, rotation: .degrees(-3))
                    .offset(x: w * 0.50, y: h * 0.40)
                    .zIndex(3)

                // 4. 顶层右侧主图（images[0]）：右倾 +3°
                photoCard(images[0], width: cardW, height: cardH, rotation: .degrees(3))
                    .offset(x: w * 0.61, y: h * 0.24)
                    .zIndex(4)
            } else if count == 3 {
                // 1. 最左侧卡片（images[1]）：底层左倾 -7°
                photoCard(images[1], width: cardW, height: cardH, rotation: .degrees(-7))
                    .offset(x: w * 0.43, y: h * 0.16)
                    .zIndex(1)

                // 2. 底部下图（images[2]）：往左旋转 3°
                photoCard(images[2], width: cardW, height: cardH, rotation: .degrees(-3))
                    .offset(x: w * 0.50, y: h * 0.38)
                    .zIndex(2)

                // 3. 顶层右侧主图（images[0]）：右倾 +3°
                photoCard(images[0], width: cardW, height: cardH, rotation: .degrees(3))
                    .offset(x: w * 0.60, y: h * 0.24)
                    .zIndex(3)
            } else if count == 2 {
                // 1. 底层左倾 -6°
                photoCard(images[1], width: cardW, height: cardH, rotation: .degrees(-6))
                    .offset(x: w * 0.44, y: h * 0.21)
                    .zIndex(1)

                // 2. 顶层右倾 +3°
                photoCard(images[0], width: cardW, height: cardH, rotation: .degrees(3))
                    .offset(x: w * 0.60, y: h * 0.25)
                    .zIndex(2)
            } else if count == 1 {
                // 1 张
                photoCard(images[0], width: cardW * 1.05, height: cardH * 1.05, rotation: .degrees(-2))
                    .offset(x: w * 0.54, y: h * 0.24)
                    .zIndex(1)
            }
        }
    }

    private func photoCard(
        _ image: UIImage,
        width: CGFloat,
        height: CGFloat,
        rotation: Angle = .zero
    ) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: max(0, width - OnThisDayVisualConstants.cardBorderWidth * 2),
                   height: max(0, height - OnThisDayVisualConstants.cardBorderWidth * 2))
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: OnThisDayVisualConstants.cardImageCornerRadius, style: .continuous))
            .padding(OnThisDayVisualConstants.cardBorderWidth)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: OnThisDayVisualConstants.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OnThisDayVisualConstants.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(isDark ? 0.28 : 0.18),
                    radius: OnThisDayVisualConstants.cardShadowRadius,
                    y: OnThisDayVisualConstants.cardShadowY)
            .rotationEffect(rotation)
    }
}
