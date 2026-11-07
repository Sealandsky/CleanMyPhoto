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
        .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 4)
        .rotationEffect(rotation)
    }
}

// MARK: - On This Day Year Page View
/// 「过去的今天」单个年份的大照片错落拼贴页组件：
/// - 单页撑满外层横幅；
/// - 1:1 复刻参考图 5 张照片错落版式：
///   左侧 2 张（左上 p1 出血探出、左下 p2 垫底微倾斜）；
///   右侧 3 张（右上 p3 出血、右下 p4 衬底、最右 p5 侧立出血）；
/// - 左右留出充足中央间隙（左右间距 ≥ 90pt），确保底层中央年份文字完整可见；
/// - 内部 ScrollView 使用 .scrollClipDisabled()，翻页时每张照片完整平移进出，不被分页硬切；
/// - 差速视差位移（外缘 0.32~0.34、内缘 0.18~0.24），落定后视差归零。
struct OnThisDayYearPageView: View {
    let group: OnThisDayYearGroup
    let pageIndex: Int
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    let scrollOffsetX: CGFloat
    let reduceMotion: Bool

    /// 页面偏离视口中心的距离（本页居中时 delta == 0）
    private var delta: CGFloat {
        guard !reduceMotion else { return 0 }
        let pageHomeX = CGFloat(pageIndex) * containerWidth
        return scrollOffsetX - pageHomeX
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
            // 5 张照片版式（1:1 精确复刻参考图）
            // 1. p2: 左下半身 (垫在 p1 右后侧)
            ScatteredPhotoCard(
                asset: photos[1],
                width: 86,
                height: 90,
                rotation: .degrees(-2)
            )
            .offset(x: 36 + delta * 0.20, y: containerHeight - 90 + 6)
            .zIndex(1)

            // 2. p1: 左上大头 (出血探出左上角)
            ScatteredPhotoCard(
                asset: photos[0],
                width: 94,
                height: 102,
                rotation: .degrees(-8)
            )
            .offset(x: -12 + delta * 0.32, y: -8)
            .zIndex(2)

            // 3. p4: 右下小图 (垫在 p3 下侧)
            ScatteredPhotoCard(
                asset: photos[3],
                width: 78,
                height: 84,
                rotation: .degrees(3)
            )
            .offset(x: (containerWidth - 78 - 50) + delta * 0.24, y: containerHeight - 84 + 6)
            .zIndex(1)

            // 4. p3: 右上大图 (探出上沿)
            ScatteredPhotoCard(
                asset: photos[2],
                width: 98,
                height: 90,
                rotation: .degrees(-3)
            )
            .offset(x: (containerWidth - 98 - 36) + delta * 0.18, y: -10)
            .zIndex(2)

            // 5. p5: 最右侧立 (探出右沿)
            ScatteredPhotoCard(
                asset: photos[4],
                width: 92,
                height: 104,
                rotation: .degrees(8)
            )
            .offset(x: (containerWidth - 92 + 10) + delta * 0.34, y: 4)
            .zIndex(3)
        } else if count == 4 {
            // 4 张照片
            ScatteredPhotoCard(
                asset: photos[1],
                width: 86,
                height: 90,
                rotation: .degrees(-2)
            )
            .offset(x: 36 + delta * 0.20, y: containerHeight - 90 + 6)
            .zIndex(1)

            ScatteredPhotoCard(
                asset: photos[0],
                width: 94,
                height: 102,
                rotation: .degrees(-8)
            )
            .offset(x: -12 + delta * 0.32, y: -8)
            .zIndex(2)

            ScatteredPhotoCard(
                asset: photos[2],
                width: 98,
                height: 90,
                rotation: .degrees(-3)
            )
            .offset(x: (containerWidth - 98 - 36) + delta * 0.18, y: -10)
            .zIndex(2)

            ScatteredPhotoCard(
                asset: photos[3],
                width: 92,
                height: 104,
                rotation: .degrees(8)
            )
            .offset(x: (containerWidth - 92 + 10) + delta * 0.34, y: 4)
            .zIndex(3)
        } else if count == 3 {
            // 3 张照片
            ScatteredPhotoCard(
                asset: photos[1],
                width: 86,
                height: 90,
                rotation: .degrees(-2)
            )
            .offset(x: 36 + delta * 0.20, y: containerHeight - 90 + 6)
            .zIndex(1)

            ScatteredPhotoCard(
                asset: photos[0],
                width: 94,
                height: 102,
                rotation: .degrees(-7)
            )
            .offset(x: -10 + delta * 0.30, y: -6)
            .zIndex(2)

            ScatteredPhotoCard(
                asset: photos[2],
                width: 94,
                height: 104,
                rotation: .degrees(7)
            )
            .offset(x: (containerWidth - 94 + 8) + delta * 0.32, y: 2)
            .zIndex(3)
        } else if count == 2 {
            // 2 张照片
            ScatteredPhotoCard(
                asset: photos[0],
                width: 94,
                height: 102,
                rotation: .degrees(-6)
            )
            .offset(x: 14 + delta * 0.26, y: 4)

            ScatteredPhotoCard(
                asset: photos[1],
                width: 94,
                height: 102,
                rotation: .degrees(6)
            )
            .offset(x: (containerWidth - 94 - 14) + delta * 0.26, y: 4)
        } else if count == 1 {
            // 1 张照片
            ScatteredPhotoCard(
                asset: photos[0],
                width: 94,
                height: 102,
                rotation: .degrees(-5)
            )
            .offset(x: 20 + delta * 0.22, y: 4)
        }
    }
}
