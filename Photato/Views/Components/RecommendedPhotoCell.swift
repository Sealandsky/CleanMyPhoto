import SwiftUI
import Photos

// MARK: - Recommended Photo Cell
/// 适合当前相簿的推荐照片卡片：
/// - 正方形圆角卡片展示图片/视频
/// - 右上角常驻浮动「+」号添加按钮（支持加载、已添加状态动画反馈）
/// - 点击图片主体调起全屏大图预览，点击「+」添加进当前相簿
struct RecommendedPhotoCell: View {
    let photo: PhotoAsset
    var isAdding: Bool = false
    var isAdded: Bool = false
    let onAdd: () -> Void
    let onTap: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var imageLoaded = false

    private static let minPixelEdge: CGFloat = 600
    private static let maxPixelEdge: CGFloat = 1400

    var body: some View {
        GeometryReader { geometry in
            let rawWidth = geometry.size.width * displayScale
            let rawHeight = geometry.size.height * displayScale
            let quantizedWidth = (rawWidth / 20.0).rounded(.up) * 20.0
            let quantizedHeight = (rawHeight / 20.0).rounded(.up) * 20.0
            let pixelWidth = min(max(quantizedWidth, Self.minPixelEdge), Self.maxPixelEdge)
            let pixelHeight = min(max(quantizedHeight, Self.minPixelEdge), Self.maxPixelEdge)

            ZStack(alignment: .topTrailing) {
                // 卡片主体
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // 视频标志
                    if photo.isVideo {
                        videoBadge
                            .opacity(imageLoaded ? 1 : 0)
                            .animation(.easeIn(duration: 0.2), value: imageLoaded)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap()
                }

                // 右上角浮动添加按钮（更贴近右上角，去掉描边和投影）
                addButton
                    .padding(5)
            }
        }
        .aspectRatio(photo.pixelAspectRatio, contentMode: .fit)
    }

    // MARK: - Add Button
    private var addButton: some View {
        Button {
            guard !isAdding && !isAdded else { return }
            onAdd()
        } label: {
            ZStack {
                if isAdded {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green)
                        .frame(width: 30, height: 30)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 30, height: 30)
                }

                if isAdding {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.6)
                } else if isAdded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 38, height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Video Badge
    private var videoBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "video.fill")
                .font(.system(size: 9))
            if let duration = photo.videoDuration {
                Text(duration)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.7))
        .clipShape(Capsule())
        .padding(6)
    }
}
