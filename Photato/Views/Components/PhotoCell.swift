import SwiftUI
import Photos

struct PhotoCell: View {
    let photo: PhotoAsset
    var isSelected: Bool = false
    var isSelectMode: Bool = false
    /// 强制 1:1 显示（整理页分类网格）；默认跟随网格设置，其他页面不受影响
    var usesSquareRatio: Bool = false
    @Environment(GridSettings.self) private var gridSettings
    @Environment(\.displayScale) private var displayScale
    @State private var imageLoaded = false

    /// 缩略图请求像素下/上限：下限贴合 Retina 3x 列宽（保证极小格子仍锐利清晰），
    /// 上限防止瀑布流中超长截图把请求尺寸顶到离谱的内存占用
    private static let minPixelEdge: CGFloat = 260
    private static let maxPixelEdge: CGFloat = 900

    /// 卡片宽高比：原比例模式下用图片真实宽高比（不裁剪不变形），
    /// 否则用用户设置的固定比例。
    private var cardAspectRatio: CGFloat {
        if usesSquareRatio { return 1.0 }
        return gridSettings.isOriginalRatio ? photo.pixelAspectRatio : gridSettings.aspectRatio
    }

    var body: some View {
        GeometryReader { geometry in
            // 缩略图按实际渲染尺寸 × 屏幕倍率请求像素，以 20px 步进向上量化规整，
            // 消除不同卡片间的浮点亚像素微差，最大化 PhotoKit 与内存缓存命中率
            let rawWidth = geometry.size.width * displayScale
            let rawHeight = geometry.size.height * displayScale
            let quantizedWidth = (rawWidth / 20.0).rounded(.up) * 20.0
            let quantizedHeight = (rawHeight / 20.0).rounded(.up) * 20.0
            let pixelWidth = min(max(quantizedWidth, Self.minPixelEdge), Self.maxPixelEdge)
            let pixelHeight = min(max(quantizedHeight, Self.minPixelEdge), Self.maxPixelEdge)

            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemFill))

                AssetImage(
                    asset: photo.asset,
                    targetSize: CGSize(width: pixelWidth, height: pixelHeight),
                    contentMode: .fill,
                    placeholderColor: Color(UIColor.secondarySystemFill),
                    onLoad: { imageLoaded = true }
                )
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                mediaBadge
                    .opacity(imageLoaded ? 1 : 0)
                    .animation(.easeIn(duration: 0.2), value: imageLoaded)

                if isSelectMode && !isSelected {
                    Color.black.opacity(0.2)
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelectMode {
                    selectionIndicator
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !isSelectMode && photo.isFavorite {
                    favoriteBadge
                        .opacity(imageLoaded ? 1 : 0)
                        .animation(.easeIn(duration: 0.2), value: imageLoaded)
                }
            }
        }
        .aspectRatio(cardAspectRatio, contentMode: .fit)
    }

    private var selectionIndicator: some View {
        Group {
            if isSelected {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, design: .rounded))
                        .foregroundColor(.blue)
                }
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 26, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            }
        }
        .padding(6)
    }

    @ViewBuilder
    private var mediaBadge: some View {
        switch photo.mediaType {
        case .video:
            videoBadge
        case .livePhoto:
            livePhotoBadge
        case .gif:
            materialTextBadge("GIF")
        case .screenshot:
            materialTextBadge(String(localized: "SS"))
        case .image:
            EmptyView()
        }
    }

    private var videoBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill")
                .font(.system(size: 10, design: .rounded))
            if let duration = photo.videoDuration {
                Text(duration)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(6)
    }

    private var favoriteBadge: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.65), radius: 2.5, x: 0, y: 1)
            .padding(7)
    }

    private var livePhotoBadge: some View {
        Image(systemName: "livephoto")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(6)
    }

    private func materialTextBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(6)
    }
}

#Preview {
    PhotoCell(photo: PhotoAsset(asset: PHAsset()))
        .environment(GridSettings())
}
