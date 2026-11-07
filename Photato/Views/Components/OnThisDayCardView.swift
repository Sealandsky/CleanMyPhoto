import SwiftUI
import Photos

// MARK: - Scattered Photo Card
/// 错落拼贴照片卡片单体组件：
/// - 精致纯白等宽四周细边框（3.5pt，彻底去掉拍立得厚下巴）；
/// - 圆角 10pt，素材圆角 7pt；
/// - 柔和深色立体投影，微倾斜，与外层横幅大容器形成生动拼贴质感。
struct ScatteredPhotoCard: View {
    let asset: PhotoAsset
    let width: CGFloat
    let height: CGFloat
    let rotation: Angle

    @State private var imageLoaded = false

    private static let cornerRadius: CGFloat = 10
    private static let imageCornerRadius: CGFloat = 7

    var body: some View {
        ZStack {
            // 纯白外卡底基
            Color.white

            // 照片内容（四周均匀 3.5pt 细白边包裹，无厚下巴）
            ZStack {
                Color(UIColor.secondarySystemFill)

                if !imageLoaded {
                    Color.clear
                        .shimmering(cornerRadius: Self.imageCornerRadius)
                }

                AssetImage(
                    asset: asset.asset,
                    targetSize: CGSize(width: width * 2, height: height * 2),
                    contentMode: .fill,
                    placeholderColor: Color.clear,
                    onLoad: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            imageLoaded = true
                        }
                    }
                )
                .scaledToFill()
                .frame(width: max(0, width - 7), height: max(0, height - 7))
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Self.imageCornerRadius, style: .continuous))
                .opacity(imageLoaded ? 1 : 0)
            }
            .frame(width: max(0, width - 7), height: max(0, height - 7))
            .padding(3.5)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.20), radius: 7, x: 0, y: 3.5)
        .rotationEffect(rotation)
    }
}

// MARK: - On This Day Year Page View
/// 「过去的今天」单个年份的大照片错落拼贴页组件：
/// - 强对比版式：大特写主图(106×116) + 瘦身竖图(62×92) + 横幅宽图(108×74) + 小品方图(68×68) + 侧边微图(58×72)；
/// - 极低遮挡：高低错开，仅微弱搭角（遮挡率 < 12%），每张图主体清晰可辨；
/// - 防闪现约束：照片严格落在页面宽度内（x: 2...containerWidth - 2），横滑时下一页不提前突入或闪现；
/// - 平滑差速视差：仅在视口过渡区间生效，外缘 14pt、内缘 8pt，落定后视差归零。
struct OnThisDayYearPageView: View {
    let group: OnThisDayYearGroup
    let pageIndex: Int
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    let scrollOffsetX: CGFloat
    let reduceMotion: Bool

    /// 平滑视差位移量：对滚动偏移进行严格截断（±28pt），平滑微移，彻底杜绝远端未进场页面的过度拉扯
    private var parallax: (outer: CGFloat, inner: CGFloat) {
        guard !reduceMotion else { return (0, 0) }
        let pageHomeX = CGFloat(pageIndex) * containerWidth
        let rawDelta = scrollOffsetX - pageHomeX
        // 限制在 -28...+28 范围内微调，杜绝跨页过度拉扯导致提前闪现
        let clampedDelta = max(-28, min(28, rawDelta))
        return (outer: clampedDelta * 0.24, inner: clampedDelta * 0.16)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景透光占位，确保整页区域均可响应点击
            Color.clear
                .frame(width: containerWidth, height: containerHeight)

            // 照片错落拼贴层
            photoCollage
        }
        .frame(width: containerWidth, height: containerHeight)
    }

    @ViewBuilder
    private var photoCollage: some View {
        let photos = group.photos
        let count = photos.count

        if count >= 5 {
            // 5 张照片版式：大特写 + 瘦竖图 + 横宽图 + 小方图 + 侧边微图
            // 1. p2 (左侧瘦身竖图): 62×92pt，居左下，+4° 倾斜，仅轻搭 p1 右后侧
            ScatteredPhotoCard(
                asset: photos[1],
                width: 62,
                height: 92,
                rotation: .degrees(4)
            )
            .offset(x: 62 + parallax.inner, y: containerHeight - 92 + 6)
            .zIndex(1)

            // 2. p1 (左侧大特写主图): 106×116pt，居左上，-6° 倾斜，视觉焦点
            ScatteredPhotoCard(
                asset: photos[0],
                width: 106,
                height: 116,
                rotation: .degrees(-6)
            )
            .offset(x: -4 + parallax.outer, y: -8)
            .zIndex(2)

            // 3. p4 (右侧小品方图): 68×68pt，居右下，+5° 倾斜
            ScatteredPhotoCard(
                asset: photos[3],
                width: 68,
                height: 68,
                rotation: .degrees(5)
            )
            .offset(x: (containerWidth - 68 - 42) + parallax.inner, y: containerHeight - 68 + 6)
            .zIndex(1)

            // 4. p3 (右侧横幅宽图): 108×74pt，居右上，-3° 倾斜，右移确保中心文字（含“年”字）完全避让不遮挡
            ScatteredPhotoCard(
                asset: photos[2],
                width: 108,
                height: 74,
                rotation: .degrees(-3)
            )
            .offset(x: (containerWidth - 108 - 24) + parallax.inner, y: -8)
            .zIndex(2)

            // 5. p5 (右外侧边微图): 58×72pt，居最右侧，+7° 倾斜，微露出血呼应
            ScatteredPhotoCard(
                asset: photos[4],
                width: 58,
                height: 72,
                rotation: .degrees(7)
            )
            .offset(x: (containerWidth - 58 + 4) + parallax.outer, y: 12)
            .zIndex(3)
        } else if count == 4 {
            // 4 张照片版式
            ScatteredPhotoCard(
                asset: photos[1],
                width: 62,
                height: 92,
                rotation: .degrees(4)
            )
            .offset(x: 62 + parallax.inner, y: containerHeight - 92 + 6)
            .zIndex(1)

            ScatteredPhotoCard(
                asset: photos[0],
                width: 106,
                height: 116,
                rotation: .degrees(-6)
            )
            .offset(x: -4 + parallax.outer, y: -8)
            .zIndex(2)

            ScatteredPhotoCard(
                asset: photos[3],
                width: 68,
                height: 68,
                rotation: .degrees(5)
            )
            .offset(x: (containerWidth - 68 - 28) + parallax.inner, y: containerHeight - 68 + 6)
            .zIndex(1)

            ScatteredPhotoCard(
                asset: photos[2],
                width: 108,
                height: 74,
                rotation: .degrees(-3)
            )
            .offset(x: (containerWidth - 108 - 14) + parallax.inner, y: -8)
            .zIndex(2)
        } else if count == 3 {
            // 3 张照片版式
            ScatteredPhotoCard(
                asset: photos[1],
                width: 62,
                height: 92,
                rotation: .degrees(4)
            )
            .offset(x: 62 + parallax.inner, y: containerHeight - 92 + 6)
            .zIndex(1)

            ScatteredPhotoCard(
                asset: photos[0],
                width: 106,
                height: 116,
                rotation: .degrees(-6)
            )
            .offset(x: -2 + parallax.outer, y: -8)
            .zIndex(2)

            ScatteredPhotoCard(
                asset: photos[2],
                width: 108,
                height: 74,
                rotation: .degrees(-3)
            )
            .offset(x: (containerWidth - 108 - 12) + parallax.outer, y: 12)
            .zIndex(2)
        } else if count == 2 {
            // 2 张照片版式
            ScatteredPhotoCard(
                asset: photos[0],
                width: 106,
                height: 116,
                rotation: .degrees(-5)
            )
            .offset(x: 6 + parallax.outer, y: 2)

            ScatteredPhotoCard(
                asset: photos[1],
                width: 108,
                height: 74,
                rotation: .degrees(4)
            )
            .offset(x: (containerWidth - 108 - 8) + parallax.outer, y: 18)
        } else if count == 1 {
            // 1 张照片
            ScatteredPhotoCard(
                asset: photos[0],
                width: 106,
                height: 116,
                rotation: .degrees(-4)
            )
            .offset(x: 14 + parallax.outer, y: 2)
        }
    }
}
