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

    private static let cornerRadius: CGFloat = 9
    private static let imageCornerRadius: CGFloat = 7

    var body: some View {
        ZStack {
            // 纯白外卡底基
            Color.white

            // 照片内容（四周均匀 2pt 细白边包裹，精致无厚下巴）
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
                .frame(width: max(0, width - 4), height: max(0, height - 4))
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Self.imageCornerRadius, style: .continuous))
                .opacity(imageLoaded ? 1 : 0)
            }
            .frame(width: max(0, width - 4), height: max(0, height - 4))
            .padding(2)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
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

    /// 平滑视差位移量：仅在当前页与邻页的翻页过渡区间产生微动，在静止或远端时严格衰减为 0，彻底杜绝跨页偷跑
    private var parallax: (outer: CGFloat, inner: CGFloat) {
        guard !reduceMotion else { return (0, 0) }
        let pageHomeX = CGFloat(pageIndex) * containerWidth
        let offsetFromCenter = scrollOffsetX - pageHomeX
        guard abs(offsetFromCenter) < containerWidth else { return (0, 0) }
        let progress = offsetFromCenter / containerWidth
        // 钟形平滑过渡：翻页正中 (progress = ±0.5) 达到最大微弱视差位移 (约 ±6pt / ±3.5pt)，
        // 当页面在中央落定 (progress = 0) 或邻页落定 (progress = ±1) 时，视差严格归零，杜绝任何静止残留偏移
        let bell = progress * (1.0 - abs(progress))
        return (outer: bell * 24, inner: bell * 14)
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
            // 5 张照片版式：主图适度缩小(92×102) + 瘦竖图(56×84) + 横宽图(108×74) + 小方图(68×68) + 侧边微图(58×72)
            // 1. p2 (左侧瘦身竖图): 56×84pt，居左下，+4° 倾斜，大幅露出减少遮挡
            ScatteredPhotoCard(
                asset: photos[1],
                width: 56,
                height: 84,
                rotation: .degrees(4)
            )
            .offset(x: 66 + parallax.inner, y: containerHeight - 84 + 8)
            .zIndex(1)

            // 2. p1 (左侧大特写主图): 92×102pt，体量适中、上提(y: -18)、不贴左边(x: 14)，-6° 倾斜，底图大半完整露出
            ScatteredPhotoCard(
                asset: photos[0],
                width: 92,
                height: 102,
                rotation: .degrees(-6)
            )
            .offset(x: 14 + parallax.outer, y: -18)
            .zIndex(2)

            // 3. p4 (右侧小品方图): 68×68pt，居右下，+5° 倾斜
            ScatteredPhotoCard(
                asset: photos[3],
                width: 68,
                height: 68,
                rotation: .degrees(5)
            )
            .offset(x: (containerWidth - 68 - 44) + parallax.inner, y: containerHeight - 68 + 6)
            .zIndex(1)

            // 4. p3 (右侧横幅宽图): 108×74pt，居右上，-3° 倾斜，确保中心文字完全避让不遮挡
            ScatteredPhotoCard(
                asset: photos[2],
                width: 108,
                height: 74,
                rotation: .degrees(-3)
            )
            .offset(x: (containerWidth - 108 - 26) + parallax.inner, y: -8)
            .zIndex(2)

            // 5. p5 (右外侧边微图): 58×72pt，居最右侧，+7° 倾斜，内收留出边距彻底不溢出下一页
            ScatteredPhotoCard(
                asset: photos[4],
                width: 58,
                height: 72,
                rotation: .degrees(7)
            )
            .offset(x: (containerWidth - 58 - 10) + parallax.outer, y: 12)
            .zIndex(3)
        } else if count == 4 {
            // 4 张照片版式
            ScatteredPhotoCard(
                asset: photos[1],
                width: 56,
                height: 84,
                rotation: .degrees(4)
            )
            .offset(x: 66 + parallax.inner, y: containerHeight - 84 + 8)
            .zIndex(1)

            ScatteredPhotoCard(
                asset: photos[0],
                width: 92,
                height: 102,
                rotation: .degrees(-6)
            )
            .offset(x: 14 + parallax.outer, y: -18)
            .zIndex(2)

            ScatteredPhotoCard(
                asset: photos[3],
                width: 68,
                height: 68,
                rotation: .degrees(5)
            )
            .offset(x: (containerWidth - 68 - 36) + parallax.inner, y: containerHeight - 68 + 6)
            .zIndex(1)

            ScatteredPhotoCard(
                asset: photos[2],
                width: 108,
                height: 74,
                rotation: .degrees(-3)
            )
            .offset(x: (containerWidth - 108 - 18) + parallax.inner, y: -8)
            .zIndex(2)
        } else if count == 3 {
            // 3 张照片版式
            ScatteredPhotoCard(
                asset: photos[1],
                width: 56,
                height: 84,
                rotation: .degrees(4)
            )
            .offset(x: 66 + parallax.inner, y: containerHeight - 84 + 8)
            .zIndex(1)

            ScatteredPhotoCard(
                asset: photos[0],
                width: 92,
                height: 102,
                rotation: .degrees(-6)
            )
            .offset(x: 14 + parallax.outer, y: -18)
            .zIndex(2)

            ScatteredPhotoCard(
                asset: photos[2],
                width: 108,
                height: 74,
                rotation: .degrees(-3)
            )
            .offset(x: (containerWidth - 108 - 16) + parallax.outer, y: 12)
            .zIndex(2)
        } else if count == 2 {
            // 2 张照片版式
            ScatteredPhotoCard(
                asset: photos[0],
                width: 92,
                height: 102,
                rotation: .degrees(-5)
            )
            .offset(x: 14 + parallax.outer, y: -4)

            ScatteredPhotoCard(
                asset: photos[1],
                width: 108,
                height: 74,
                rotation: .degrees(4)
            )
            .offset(x: (containerWidth - 108 - 14) + parallax.outer, y: 18)
        } else if count == 1 {
            // 1 张照片
            ScatteredPhotoCard(
                asset: photos[0],
                width: 92,
                height: 102,
                rotation: .degrees(-4)
            )
            .offset(x: 18 + parallax.outer, y: 2)
        }
    }
}
