import SwiftUI
import Photos

struct PhotoCell: View {
    let photo: PhotoAsset
    var isSelected: Bool = false
    var isSelectMode: Bool = false
    /// 强制 1:1 显示（整理页分类网格）；默认跟随网格设置，其他页面不受影响
    var usesSquareRatio: Bool = false
    /// 强制按真实宽高比原比例展示（瀑布流/相簿推荐/详情页相似模块）
    var forceOriginalRatio: Bool = false
    /// 圆角大小，默认 16（相簿推荐可传 14，详情页相似可传 24）
    var cornerRadius: CGFloat = 16
    /// 是否展示角标（视频时长、收藏心标等），默认 true
    var showBadges: Bool = true

    /// 浮动添加按钮相关（相簿推荐等场景）
    var isAdding: Bool = false
    var isAdded: Bool = false
    var onAdd: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @Environment(GridSettings.self) private var gridSettings: GridSettings?
    @Environment(\.displayScale) private var displayScale
    @State private var imageLoaded = false

    /// 卡片宽高比：原比例模式下用图片真实宽高比（不裁剪不变形），
    /// 否则用用户设置的固定比例。
    private var cardAspectRatio: CGFloat {
        if usesSquareRatio { return 1.0 }
        if forceOriginalRatio { return photo.pixelAspectRatio }
        if let gridSettings = gridSettings {
            return gridSettings.isOriginalRatio ? photo.pixelAspectRatio : gridSettings.aspectRatio
        }
        return photo.pixelAspectRatio
    }

    var body: some View {
        GeometryReader { geometry in
            // 缩略图基准尺寸：采用统一的标准物理像素尺寸，
            // 消除不同卡片间的浮点微差，并防御 GeometryReader 初始测量为 0 的抖动，与后台预热 100% 咬合
            let thumbnailSize: CGSize = {
                let columns = usesSquareRatio ? 3 : (gridSettings?.columnCount ?? 2)
                if geometry.size.width > 20 {
                    let rawWidth = geometry.size.width * displayScale
                    let rawHeight = geometry.size.height * displayScale
                    let quantizedWidth = (rawWidth / 20.0).rounded(.up) * 20.0
                    let quantizedHeight = (rawHeight / 20.0).rounded(.up) * 20.0
                    let widthEdge = min(max(quantizedWidth, GridColumnHelper.minPixelEdge), GridColumnHelper.maxPixelEdge)
                    let heightEdge = min(max(quantizedHeight, GridColumnHelper.minPixelEdge), GridColumnHelper.maxPixelEdge)
                    let edge = max(widthEdge, heightEdge)
                    return CGSize(width: edge, height: edge)
                } else {
                    return GridColumnHelper.thumbnailPixelSize(columnCount: columns)
                }
            }()

            cardContainer(geometry: geometry, thumbnailSize: thumbnailSize)
        }
        .aspectRatio(cardAspectRatio, contentMode: .fit)
    }

    @ViewBuilder
    private func cardContainer(geometry: GeometryProxy, thumbnailSize: CGSize) -> some View {
        let content = cardContent(geometry: geometry, thumbnailSize: thumbnailSize)
        if let onTap = onTap {
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap()
                }
        } else {
            content
        }
    }

    private func cardContent(geometry: GeometryProxy, thumbnailSize: CGSize) -> some View {
        ZStack(alignment: .topTrailing) {
            // 卡片主体
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(UIColor.secondarySystemFill))

                // 加载中扫光动画：覆盖在底层灰色上，就绪时平滑淡出
                if !imageLoaded {
                    Color.clear
                        .shimmering(cornerRadius: cornerRadius)
                        .transition(.opacity)
                }

                AssetImage(
                    asset: photo.asset,
                    targetSize: thumbnailSize,
                    contentMode: .fill,
                    placeholderColor: Color.clear,
                    onLoad: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            imageLoaded = true
                        }
                    }
                )
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity(imageLoaded ? 1 : 0)

                if showBadges {
                    mediaBadge
                        .opacity(imageLoaded ? 1 : 0)
                        .animation(.easeIn(duration: 0.2), value: imageLoaded)
                }

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
                if showBadges && !isSelectMode && photo.isFavorite {
                    favoriteBadge
                        .opacity(imageLoaded ? 1 : 0)
                        .animation(.easeIn(duration: 0.2), value: imageLoaded)
                }
            }

            // 右上角浮动操作按钮（如相簿推荐「+」添加按钮）
            if onAdd != nil {
                addButton
                    .padding(5)
            }
        }
    }

    // MARK: - Add Button
    private var addButton: some View {
        Button {
            guard !isAdding && !isAdded else { return }
            onAdd?()
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
