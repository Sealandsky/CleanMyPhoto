import SwiftUI
import Photos

struct PhotoCell: View {
    let photo: PhotoAsset
    var isSelected: Bool = false
    var isSelectMode: Bool = false
    /// 强制 1:1 显示（整理页分类网格）；默认跟随网格设置，其他页面不受影响
    var usesSquareRatio: Bool = false
    @Environment(GridSettings.self) private var gridSettings
    @State private var imageLoaded = false

    /// 卡片宽高比：原比例模式下用图片真实宽高比（不裁剪不变形），
    /// 否则用用户设置的固定比例。
    private var cardAspectRatio: CGFloat {
        if usesSquareRatio { return 1.0 }
        return gridSettings.isOriginalRatio ? photo.pixelAspectRatio : gridSettings.aspectRatio
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)

                AssetImage(
                    asset: photo.asset,
                    targetSize: CGSize(width: 400, height: 400),
                    contentMode: .fill,
                    placeholderColor: .white,
                    onLoad: { imageLoaded = true }
                )
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                mediaBadge
                    .opacity(imageLoaded ? 1 : 0)

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
                }
            }
        }
        .aspectRatio(cardAspectRatio, contentMode: .fit)
        .animation(.easeIn(duration: 0.2), value: imageLoaded)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(6)
    }

    private var favoriteBadge: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.45), radius: 2, x: 0, y: 1)
            .padding(7)
    }

    private var livePhotoBadge: some View {
        Image(systemName: "livephoto")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
    }

    private func materialTextBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
    }
}

#Preview {
    PhotoCell(photo: PhotoAsset(asset: PHAsset()))
        .environment(GridSettings())
}
