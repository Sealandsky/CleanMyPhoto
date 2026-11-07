import SwiftUI
import Photos

// MARK: - Polaroid Photo Card
/// 拍立得风格照片卡片单体组件：
/// - 纯白外卡基底，带柔和深色立体投影；
/// - 内部素材四周白边包裹，底部保留经典拍立得 16pt 厚白边；
/// - 边框白色细描边，微倾斜，与外层 3:1 横幅大容器形成饱满拼贴质感。
struct PolaroidPhotoCard: View {
    let asset: PhotoAsset
    let width: CGFloat
    let height: CGFloat
    let rotation: Angle

    @State private var imageLoaded = false

    private static let cornerRadius: CGFloat = 6
    private static let imageCornerRadius: CGFloat = 4

    var body: some View {
        ZStack {
            // 1. 纯白拍立得外卡
            Color.white

            // 2. 照片内容区域（四周 4pt 白边，底部 16pt 厚边）
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
                .frame(width: max(0, width - 8), height: max(0, height - 20))
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Self.imageCornerRadius, style: .continuous))
                .opacity(imageLoaded ? 1 : 0)
            }
            .frame(width: max(0, width - 8), height: max(0, height - 20))
            .padding(.top, 4)
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.38), radius: 7, x: 0, y: 3.5)
        .rotationEffect(rotation)
    }
}

// MARK: - On This Day Year Page View
/// 「过去的今天」单个年份的大照片拼贴页组件：
/// - 单页尺寸撑满外层横幅（宽 containerWidth × 高 containerHeight）；
/// - 照片大尺寸（92×116pt）撑满上下，不做缩小留白；
/// - 内部 ScrollView 使用 .scrollClipDisabled()，翻页时每张照片完整平移进出，不被分页硬切；
/// - 左右双层差速视差位移（外缘 0.32、内缘 0.18），落定后视差归零。
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

    private static let cardW: CGFloat = 92
    private static let cardH: CGFloat = 116

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景透光占位，确保整页区域均可响应点击
            Color.clear
                .frame(width: containerWidth, height: containerHeight)

            // 照片拼贴层
            photoCollage
        }
        .frame(width: containerWidth, height: containerHeight)
    }

    @ViewBuilder
    private var photoCollage: some View {
        let photos = group.photos
        let count = photos.count
        let innerOffset = max(42, containerWidth * 0.15)

        if count >= 4 {
            // 4 张照片（左右各 2 张，微倾斜错落拼贴）
            // 绘制顺序：内侧先画垫底，外侧后画在顶层
            // p2 (内左)
            PolaroidPhotoCard(
                asset: photos[1],
                width: Self.cardW,
                height: Self.cardH,
                rotation: .degrees(4)
            )
            .offset(x: innerOffset + delta * 0.18, y: -4)

            // p3 (内右)
            PolaroidPhotoCard(
                asset: photos[2],
                width: Self.cardW,
                height: Self.cardH,
                rotation: .degrees(-4)
            )
            .offset(x: (containerWidth - Self.cardW - innerOffset) + delta * 0.18, y: -4)

            // p1 (外左)
            PolaroidPhotoCard(
                asset: photos[0],
                width: Self.cardW,
                height: Self.cardH,
                rotation: .degrees(-6)
            )
            .offset(x: -8 + delta * 0.32, y: 2)

            // p4 (外右)
            PolaroidPhotoCard(
                asset: photos[3],
                width: Self.cardW,
                height: Self.cardH,
                rotation: .degrees(6)
            )
            .offset(x: (containerWidth - Self.cardW + 8) + delta * 0.32, y: 2)
        } else if count == 3 {
            // 3 张照片
            PolaroidPhotoCard(
                asset: photos[1],
                width: Self.cardW,
                height: Self.cardH,
                rotation: .degrees(4)
            )
            .offset(x: innerOffset + delta * 0.18, y: -4)

            PolaroidPhotoCard(
                asset: photos[0],
                width: Self.cardW,
                height: Self.cardH,
                rotation: .degrees(-6)
            )
            .offset(x: -8 + delta * 0.32, y: 2)

            PolaroidPhotoCard(
                asset: photos[2],
                width: Self.cardW,
                height: Self.cardH,
                rotation: .degrees(6)
            )
            .offset(x: (containerWidth - Self.cardW + 8) + delta * 0.32, y: 2)
        } else if count == 2 {
            // 2 张照片（左右各一张）
            PolaroidPhotoCard(
                asset: photos[0],
                width: Self.cardW,
                height: Self.cardH,
                rotation: .degrees(-5)
            )
            .offset(x: 16 + delta * 0.26, y: 2)

            PolaroidPhotoCard(
                asset: photos[1],
                width: Self.cardW,
                height: Self.cardH,
                rotation: .degrees(5)
            )
            .offset(x: (containerWidth - Self.cardW - 16) + delta * 0.26, y: 2)
        } else if count == 1 {
            // 1 张照片
            PolaroidPhotoCard(
                asset: photos[0],
                width: Self.cardW,
                height: Self.cardH,
                rotation: .degrees(-4)
            )
            .offset(x: 20 + delta * 0.22, y: 2)
        }
    }
}
